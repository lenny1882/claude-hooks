#!/usr/bin/env bash
# Remove handoff-gate from this machine.
#
#   ./uninstall.sh                 ask before editing settings.json
#   ./uninstall.sh --yes           no prompts
#   ./uninstall.sh --keep-settings leave settings.json alone
#   ./uninstall.sh --keep-state    keep the package's state for a later reinstall

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
SETTINGS="$CLAUDE_DIR/settings.json"
LIB_DIR="$HOME/.local/share/handoff-gate"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/handoff-gate"

ASSUME_YES=0; KEEP_SETTINGS=0; KEEP_STATE=0
for a in "$@"; do
  case "$a" in
    --yes|-y)        ASSUME_YES=1 ;;
    --keep-settings) KEEP_SETTINGS=1 ;;
    --keep-state)    KEEP_STATE=1 ;;
    -h|--help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done

ok()   { printf '  ok    %s\n' "$*"; }
warn() { printf '  warn  %s\n' "$*"; }
step() { printf '\n== %s\n' "$*"; }
confirm() {
  [ "$ASSUME_YES" -eq 1 ] && return 0
  local reply; read -r -p "$1 [Y/n] " reply </dev/tty || return 1
  case "$reply" in [Nn]*) return 1 ;; *) return 0 ;; esac
}

FILES=(); DIRS=(); STATE_DIRS=()
# shellcheck source=manifest.sh
. "$REPO/manifest.sh"

# A package's state: state/ inside a skill's installed directory, and
# $CLAUDE_DIR/$PKG for a hook or command package, which has no directory of its
# own. Both go unless --keep-state. With --link the skill's directory is a
# symlink, so removing it leaves state/ in the checkout, where git ignores it.
PKG_STATE="$CLAUDE_DIR/$PKG"

# Claude Code's own directories, and other tools', under ~/.claude. A package
# with one of these names would have its state at that path, and removing it
# would take their data with it. new-package.sh refuses these names; this is
# the backstop for a package named before it did.
RESERVED=" agents auth-recipes backups bin bridge-spawn cache commands daemon
  debug dev-mods downloads feedback file-history hooks ide jobs local logs
  memory output-styles paste-cache plugins projects reference rules routines
  seed-admin session-colors session-env sessions shares shell-snapshots skills
  state statsig statusline-state todos uploads workflows "

printf '%s\n' "== Uninstalling $PKG"

# pre_uninstall runs while the package is still installed, for anything that
# needs its files to undo — services started from inside the skill's directory,
# say. If it fails, nothing is removed.
if declare -F pre_uninstall >/dev/null; then
  step "Before removing anything"
  if pre_uninstall; then ok "pre_uninstall"
  else echo "pre_uninstall failed — nothing removed." >&2; exit 1; fi
fi

step "Removing files"
for entry in ${FILES[@]+"${FILES[@]}"} ${DIRS[@]+"${DIRS[@]}"}; do
  d="${entry#*:}" keep=""
  if [ "$KEEP_STATE" -eq 1 ] && [ -d "$d/state" ] && [ ! -L "$d" ]; then
    keep=$(mktemp -d "$(dirname "$d")/.$(basename "$d").state.XXXXXX")
    mv "$d/state" "$keep/state"
  fi
  if [ -e "$d" ] || [ -L "$d" ]; then rm -rf "$d"; ok "removed $d"; else ok "no $d"; fi
  if [ -n "$keep" ]; then
    mkdir -p "$d"; mv "$keep/state" "$d/state"; rmdir "$keep"
    ok "kept $d/state (--keep-state)"
  fi
done
case "$(printf '%s' "$RESERVED" | tr -s ' \n' ' ')" in
  *" $PKG "*) warn "not removing $PKG_STATE: that name belongs to Claude Code or another tool" ;;
  *) if [ -d "$PKG_STATE" ]; then
       if [ "$KEEP_STATE" -eq 1 ]; then ok "kept $PKG_STATE (--keep-state)"
       else rm -rf "$PKG_STATE"; ok "removed $PKG_STATE"; fi
     fi ;;
esac
for d in "$LIB_DIR" "$STATE" ${STATE_DIRS[@]+"${STATE_DIRS[@]}"}; do
  [ -d "$d" ] && { rm -rf "$d"; ok "removed $d"; }
done

step "settings.json"
if [ "$KEEP_SETTINGS" -eq 1 ]; then
  ok "left alone (--keep-settings)"
elif [ ! -f "$SETTINGS" ]; then
  ok "no $SETTINGS"
elif ! jq empty "$SETTINGS" 2>/dev/null; then
  warn "$SETTINGS is not valid JSON — leaving it untouched."
  warn "Remove the hook entries whose command contains '$OWNS' or one of its script names by hand."
elif confirm "  Remove this package's hook entries?"; then
  cp "$SETTINGS" "$SETTINGS.bak-uninstall"
  # Match OWNS and each installed script's basename, each as a whole word, as
  # install.sh does: a package bundling several hooks removes the entries of
  # every one of them, and none of a sibling whose name merely starts the same.
  owns_json=$(
    { [ -n "${OWNS:-}" ] && printf '%s\n' "$OWNS"
      for entry in ${FILES[@]+"${FILES[@]}"}; do basename "${entry#*:}"; done
    } | sort -u | jq -R . | jq -s .
  )
  tmp=$(mktemp)
  jq --argjson owns "$owns_json" '
    def ours: (.command // "") as $c
      | any($owns[]; gsub("[.]"; "\\.") as $o
          | $c | test("(^|[^A-Za-z0-9_-])" + $o + "($|[^A-Za-z0-9_-])"));
    def strip_ours: map(.hooks |= map(select(ours | not))) | map(select((.hooks | length) > 0));
    if (.hooks | type) == "object" then
      .hooks |= with_entries(if (.value | type) == "array" then .value |= strip_ours else . end)
      | .hooks |= with_entries(select((.value | type) != "array" or (.value | length) > 0))
      | (if (.hooks // null) == {} then del(.hooks) else . end)
    else . end
  ' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
  ok "cleaned; previous file saved as $SETTINGS.bak-uninstall"
else
  ok "left alone"
fi

printf '\n%s\n' "Done."
