#!/usr/bin/env bash
# Tests for handoff-gate.
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
jq -e '[.. | .command? // empty] | any(test("precompact-handoff\\.sh"))' \
  "$CLAUDE_DIR/settings.json" >/dev/null 2>&1 \
  && no "uninstall removes the hook scripts' entries" "still registered" \
  || ok "uninstall removes the hook scripts' entries"

HOOK="$REPO/hooks/precompact-handoff.sh"
PROJ="$TMP/proj"
mkdir -p "$HOME/.claude" "$PROJ"

# Run the hook the way Claude Code does: JSON on stdin.
run(){ # run <mode> <cwd> [custom_instructions]
  jq -nc --arg c "$2" --arg ci "${3:-}" \
    '{session_id:"sess1",cwd:$c,transcript_path:"/nonexistent",
      hook_event_name:"PreCompact",trigger:"manual",custom_instructions:$ci}' \
  | "$HOOK" "$1" >"$TMP/out" 2>"$TMP/err"
  echo $?
}

expect(){ # expect <description> <expected exit> <actual exit>
  [ "$2" = "$3" ] && ok "$1" || no "$1" "expected exit $2, got $3"
}

echo "gate cycle"
expect "first /compact is cancelled"            2 "$(run gate "$PROJ")"
expect "wake side asks for the handoff"         2 "$(run wake "$PROJ")"
grep -q "Cover where the work actually stands" "$TMP/err" \
  && ok "wake explains what to write" || no "wake explains what to write" "instructions missing"

sleep 0.05; touch "$PROJ/HANDOFF.md"
expect "handoff written, /compact passes"       0 "$(run gate "$PROJ")"
grep -q "preserve" "$TMP/out" \
  && ok "passing feeds instructions to the summary" || no "passing feeds instructions to the summary" "stdout empty"
expect "work has moved on, cancelled again"     2 "$(run gate "$PROJ")"

echo "escape hatches"
expect "/compact skip handoff"                  0 "$(run gate "$PROJ" "skip handoff")"
expect "case does not matter"                   0 "$(run gate "$PROJ" "Skip Handoff please")"
touch "$PROJ/.nohandoff"
expect ".nohandoff opts the directory out"      0 "$(run gate "$PROJ")"
rm -f "$PROJ/.nohandoff"

echo "target selection"
GSD="$TMP/gsd"; mkdir -p "$GSD/.planning"
run gate "$GSD" >/dev/null
grep -q "gsd:pause-work" "$TMP/err" \
  && ok "a .planning project is sent to /gsd:pause-work" || no "a .planning project is sent to /gsd:pause-work" "$(cat "$TMP/err")"
run wake "$GSD" >/dev/null
grep -q ".continue-here.md" "$TMP/err" \
  && ok "and to .continue-here.md, not HANDOFF.md" || no "and to .continue-here.md, not HANDOFF.md" "$(cat "$TMP/err")"

echo "installer — beside another Stop hook"
printf '{"model":"Opus","hooks":{"Stop":[{"hooks":[{"type":"command","command":"true"}]}]}}\n' > "$CLAUDE_DIR/settings.json"
"$REPO/install.sh" --link --yes >/dev/null 2>&1
n=$(jq '[.hooks.PreCompact[].hooks[]] | length' "$CLAUDE_DIR/settings.json")
[ "$n" = 2 ] && ok "installs both hooks" || no "installs both hooks" "got $n"
jq -e '.hooks.Stop' "$CLAUDE_DIR/settings.json" >/dev/null \
  && ok "leaves other hooks alone" || no "leaves other hooks alone" "Stop hook lost"
[ -L "$CLAUDE_DIR/hooks/precompact-handoff.sh" ] \
  && ok "--link symlinks back to the checkout" || no "--link symlinks back to the checkout" "not a symlink"

"$REPO/install.sh" --link --yes >/dev/null 2>&1
n=$(jq '[.hooks.PreCompact[].hooks[]] | length' "$CLAUDE_DIR/settings.json")
[ "$n" = 2 ] && ok "reinstalling does not duplicate" || no "reinstalling does not duplicate" "got $n"

"$REPO/uninstall.sh" --yes >/dev/null 2>&1
jq -e '.hooks.PreCompact' "$CLAUDE_DIR/settings.json" >/dev/null 2>&1 \
  && no "uninstall removes the entry" "PreCompact still present" || ok "uninstall removes the entry"
jq -e '.hooks.Stop' "$CLAUDE_DIR/settings.json" >/dev/null \
  && ok "uninstall leaves other hooks alone" || no "uninstall leaves other hooks alone" "Stop hook lost"

echo "uninstall --keep-state"
# The hook keeps its markers in ~/.claude/handoff-gate. uninstall.sh owns that
# directory; listing it in STATE_DIRS as well made --keep-state report keeping
# it and then delete it.
"$REPO/install.sh" --link --yes >/dev/null 2>&1
mkdir -p "$CLAUDE_DIR/handoff-gate"; : > "$CLAUDE_DIR/handoff-gate/marker"
"$REPO/uninstall.sh" --yes --keep-state >/dev/null 2>&1
[ -e "$CLAUDE_DIR/handoff-gate/marker" ] \
  && ok "--keep-state keeps the hook's state" || no "--keep-state keeps the hook's state" "state deleted"
"$REPO/install.sh" --link --yes >/dev/null 2>&1
"$REPO/uninstall.sh" --yes >/dev/null 2>&1
[ -e "$CLAUDE_DIR/handoff-gate" ] \
  && no "a plain uninstall removes the state" "still there" || ok "a plain uninstall removes the state"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
