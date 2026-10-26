#!/usr/bin/env bash
# Tests for inventory-guard.
#
# Redirects HOME and CLAUDE_DIR into a temp directory, so the real config is
# never touched. Add cases for the behaviour itself below the installer ones —
# the installer tests come free, the behaviour tests are the point.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
export CLAUDE_DIR="$TMP/claude"; mkdir -p "$CLAUDE_DIR"

pass=0; fail=0
ok(){ printf '  ok    %s\n' "$1"; pass=$((pass+1)); }
no(){ printf '  FAIL  %s\n    %s\n' "$1" "$2"; fail=$((fail+1)); }

. "$REPO/test/installer-tests.sh"

# The kit's "uninstall removes our entries" looks for the package name in the
# registered commands, but these commands are paths to the hook scripts and
# never contain it, so that check passes whatever uninstall leaves behind. This
# one looks for the scripts.
jq -e '[.. | .command? // empty] | any(test("inventory-check\\.sh"))' \
  "$CLAUDE_DIR/settings.json" >/dev/null 2>&1 \
  && no "uninstall removes the hook scripts' entries" "still registered" \
  || ok "uninstall removes the hook scripts' entries"

HOOK="$REPO/hooks/inventory-check.sh"
mkdir -p "$HOME/.claude/hooks" "$HOME/.claude/skills" "$HOME/.local/bin"
export CLAUDE_INVENTORY="$TMP/INVENTORY.md"

run(){ # run <session id> [stop_hook_active]
  jq -nc --arg s "$1" --argjson a "${2:-false}" \
    '{hook_event_name:"Stop",session_id:$s,stop_hook_active:$a}' \
  | bash "$HOOK" >"$TMP/out" 2>"$TMP/err"; rc=$?
  # A turn sent back to Claude shows as additionalContext on exit 0.
  [ "$rc" = 0 ] && [ -s "$TMP/out" ] && jq -e .hookSpecificOutput.additionalContext "$TMP/out" >/dev/null 2>&1 && rc=fed
  echo $rc
}

echo "nothing installed"
: > "$CLAUDE_INVENTORY"
[ "$(run s1)" = 0 ] && ok "empty config, turn ends" || no "empty config, turn ends" "blocked"

echo "an unlisted hook"
touch "$HOME/.claude/hooks/something-new.sh"
[ "$(run s2)" = fed ] && ok "blocks on an unlisted hook" || no "blocks on an unlisted hook" "did not block"
grep -q "something-new.sh" "$TMP/out" && ok "names what is missing" || no "names what is missing" "$(cat "$TMP/out")"
[ "$(run s2)" = 0 ] && ok "says it once per session" || no "says it once per session" "nagged twice"
[ "$(run s3)" = fed ] && ok "a new session is told too" || no "a new session is told too" "stayed quiet"

echo "once written down"
echo "- something-new.sh — a thing" > "$CLAUDE_INVENTORY"
[ "$(run s4)" = 0 ] && ok "listing it clears the block" || no "listing it clears the block" "still blocked"

echo "other kinds"
mkdir -p "$HOME/.claude/skills/some-skill"
[ "$(run s5)" = fed ] && ok "notices skills" || no "notices skills" "missed a skill"
echo "- some-skill" >> "$CLAUDE_INVENTORY"
touch "$HOME/.local/bin/claude-thing"
[ "$(run s6)" = fed ] && ok "notices ~/.local/bin/claude-*" || no "notices ~/.local/bin/claude-*" "missed a command"
echo "- claude-thing" >> "$CLAUDE_INVENTORY"
[ "$(run s7)" = 0 ] && ok "quiet once all are listed" || no "quiet once all are listed" "$(cat "$TMP/out")"

echo "guards"
touch "$HOME/.claude/hooks/another-new.sh"
[ "$(run s8 true)" = 0 ] && ok "honours stop_hook_active" || no "honours stop_hook_active" "blocked in a loop"
touch "$HOME/.claude/hooks/x.sh.bak-20260101"
[ "$(run s9)" = fed ] && ok "still blocks on the real one" || no "still blocks on the real one" "did not block"
grep -q "\.bak" "$TMP/out" && no "ignores .bak files" "complained about a backup" || ok "ignores .bak files"
touch "$HOME/.claude/.no-inventory-check"
[ "$(run s10)" = 0 ] && ok "opt-out silences it" || no "opt-out silences it" "still blocked"
rm -f "$HOME/.claude/.no-inventory-check"
mv "$CLAUDE_INVENTORY" "$TMP/gone.md"
[ "$(run s11)" = 0 ] && ok "no inventory file, stays quiet" || no "no inventory file, stays quiet" "blocked with nowhere to write"

echo "installer — beside claude-notify"
printf '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"claude-notify play stop"}]}]}}\n' > "$CLAUDE_DIR/settings.json"
"$REPO/install.sh" --link --yes >/dev/null 2>&1
n=$(jq '[.hooks.Stop[].hooks[]] | length' "$CLAUDE_DIR/settings.json")
[ "$n" = 2 ] && ok "adds itself beside the existing Stop hook" || no "adds itself beside the existing Stop hook" "got $n"
"$REPO/install.sh" --link --yes >/dev/null 2>&1
n=$(jq '[.hooks.Stop[].hooks[]] | length' "$CLAUDE_DIR/settings.json")
[ "$n" = 2 ] && ok "reinstalling does not duplicate" || no "reinstalling does not duplicate" "got $n"
"$REPO/uninstall.sh" --yes >/dev/null 2>&1
jq -e '[.hooks.Stop[].hooks[].command] | any(contains("claude-notify"))' "$CLAUDE_DIR/settings.json" >/dev/null \
  && ok "uninstall leaves the notify hook" || no "uninstall leaves the notify hook" "it was removed"

echo "uninstall --keep-state"
# The hook keeps its markers in ~/.claude/inventory-guard. uninstall.sh owns that
# directory; listing it in STATE_DIRS as well made --keep-state report keeping
# it and then delete it.
"$REPO/install.sh" --link --yes >/dev/null 2>&1
mkdir -p "$CLAUDE_DIR/inventory-guard"; : > "$CLAUDE_DIR/inventory-guard/marker"
"$REPO/uninstall.sh" --yes --keep-state >/dev/null 2>&1
[ -e "$CLAUDE_DIR/inventory-guard/marker" ] \
  && ok "--keep-state keeps the hook's state" || no "--keep-state keeps the hook's state" "state deleted"
"$REPO/install.sh" --link --yes >/dev/null 2>&1
"$REPO/uninstall.sh" --yes >/dev/null 2>&1
[ -e "$CLAUDE_DIR/inventory-guard" ] \
  && no "a plain uninstall removes the state" "still there" || ok "a plain uninstall removes the state"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
