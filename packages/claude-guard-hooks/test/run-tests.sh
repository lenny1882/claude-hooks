#!/usr/bin/env bash
# Tests for claude-guard-hooks.
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
jq -e '[.. | .command? // empty] | any(test("check-discuss-batch\\.sh|gate-unsandboxed-bash\\.sh"))' \
  "$CLAUDE_DIR/settings.json" >/dev/null 2>&1 \
  && no "uninstall removes the hook scripts' entries" "still registered" \
  || ok "uninstall removes the hook scripts' entries"

# Feed a hook the JSON Claude Code would. Leaves the exit code in $rc.
rc=0
call(){ # call <script> <json>
  printf '%s' "$2" | bash "$REPO/hooks/$1" >"$TMP/out" 2>"$TMP/err"; rc=$?; }
# -s first: jq -e on an empty file exits 0, which would read as a denial.
denied(){ [ -s "$TMP/out" ] \
  && jq -e '.hookSpecificOutput.permissionDecision == "deny"' "$TMP/out" >/dev/null 2>&1; }
# A UserPromptExpansion block is exit 2 with the reason on stderr.
blocked(){ [ "$rc" = 2 ] && [ -s "$TMP/err" ]; }

echo "gate-unsandboxed-bash"
j(){ jq -nc --argjson s "$1" '{hook_event_name:"PreToolUse",tool_name:"Bash",
      tool_input:{command:"ls",dangerouslyDisableSandbox:$s}}'; }
call gate-unsandboxed-bash.sh "$(j true)"
denied && ok "denies a call asking to leave the sandbox" || no "denies a call asking to leave the sandbox" "$(cat "$TMP/out")"
call gate-unsandboxed-bash.sh "$(j false)"
denied && no "lets a sandboxed call through" "denied a normal call" || ok "lets a sandboxed call through"

echo "check-discuss-batch — Claude calls the skill"
d(){ jq -nc --arg a "$1" '{hook_event_name:"PreToolUse",tool_name:"Skill",
      tool_input:{skill:"gsd:discuss-phase",args:$a}}'; }
call check-discuss-batch.sh "$(d "3")"
denied && ok "denies discuss-phase with no flag" || no "denies discuss-phase with no flag" "$(cat "$TMP/out")"
for flag in --batch --batch=5 --auto --power --no-batch; do
  call check-discuss-batch.sh "$(d "3 $flag")"
  denied && no "$flag is allowed through" "denied" || ok "$flag is allowed through"
done
call check-discuss-batch.sh "$(jq -nc '{hook_event_name:"PreToolUse",tool_name:"Skill",
      tool_input:{skill:"gsd:plan-phase",args:"3"}}')"
denied && no "other skills are untouched" "denied plan-phase" || ok "other skills are untouched"

echo "check-discuss-batch — the user types the command"
# The shape Claude Code sends: command_name is the resolved name, command_args
# the rest of the line, prompt the whole thing.
u(){ jq -nc --arg n "$1" --arg a "$2" '{hook_event_name:"UserPromptExpansion",
      expansion_type:"slash_command",command_name:$n,command_args:$a,
      command_source:"plugin",prompt:("/" + $n + " " + $a)}'; }
call check-discuss-batch.sh "$(u "gsd:discuss-phase" "3")"
blocked && ok "blocks a typed discuss-phase with no flag" || no "blocks a typed discuss-phase with no flag" "rc=$rc err=$(cat "$TMP/err")"
grep -q -- "--batch" "$TMP/err" \
  && ok "the block message names the flags" || no "the block message names the flags" "$(cat "$TMP/err")"
for flag in --batch --batch=5 --auto --power --no-batch; do
  call check-discuss-batch.sh "$(u "gsd:discuss-phase" "3 $flag")"
  blocked && no "typed $flag is allowed through" "blocked" || ok "typed $flag is allowed through"
done
call check-discuss-batch.sh "$(u "bm:discuss-phase" "3")"
blocked && ok "the /bm: prefix is caught too" || no "the /bm: prefix is caught too" "rc=$rc"
call check-discuss-batch.sh "$(u "discuss-phase" "3")"
blocked && ok "an unprefixed name is caught too" || no "an unprefixed name is caught too" "rc=$rc"
call check-discuss-batch.sh "$(u "gsd:plan-phase" "3")"
blocked && no "other slash commands are untouched" "blocked plan-phase" || ok "other slash commands are untouched"
# command_name absent — fall back to the first word of the prompt.
call check-discuss-batch.sh "$(jq -nc '{hook_event_name:"UserPromptExpansion",
      expansion_type:"slash_command",command_args:"3",prompt:"/gsd:discuss-phase 3"}')"
blocked && ok "falls back to the prompt when command_name is missing" || no "falls back to the prompt when command_name is missing" "rc=$rc"

echo "installer — beside claude-branch-guard"
cat > "$CLAUDE_DIR/settings.json" <<'JSON'
{"model":"Opus","hooks":{"PreToolUse":[{"matcher":"Skill","hooks":[
  {"type":"command","command":"~/.claude/hooks/check-branch-naming.sh"}]}]}}
JSON
count(){ jq "[.hooks[$1][]?.hooks[]] | length" "$CLAUDE_DIR/settings.json"; }

"$REPO/install.sh" --link --yes >/dev/null 2>&1
[ "$(count '"PreToolUse"')" = 3 ] && ok "adds both PreToolUse hooks without dropping the existing one" \
  || no "adds both PreToolUse hooks without dropping the existing one" "got $(count '"PreToolUse"')"
[ "$(count '"UserPromptExpansion"')" = 1 ] && ok "registers the typed-command hook" \
  || no "registers the typed-command hook" "got $(count '"UserPromptExpansion"')"
jq -e '.hooks.UserPromptExpansion[0] | has("matcher") | not' "$CLAUDE_DIR/settings.json" >/dev/null \
  && ok "the typed-command hook has no matcher" || no "the typed-command hook has no matcher" "it has one"
jq -e '[.hooks.PreToolUse[].hooks[].command] | any(contains("check-branch-naming"))' \
  "$CLAUDE_DIR/settings.json" >/dev/null \
  && ok "claude-branch-guard's hook survives" || no "claude-branch-guard's hook survives" "it was removed"

"$REPO/install.sh" --link --yes >/dev/null 2>&1
[ "$(count '"PreToolUse"')" = 3 ] && [ "$(count '"UserPromptExpansion"')" = 1 ] \
  && ok "reinstalling does not duplicate" \
  || no "reinstalling does not duplicate" "got $(count '"PreToolUse"') and $(count '"UserPromptExpansion"')"

"$REPO/uninstall.sh" --yes >/dev/null 2>&1
[ "$(count '"PreToolUse"')" = 1 ] && ok "uninstall removes only its own" || no "uninstall removes only its own" "got $(count '"PreToolUse"')"
jq -e '.hooks | has("UserPromptExpansion") | not' "$CLAUDE_DIR/settings.json" >/dev/null \
  && ok "uninstall drops the emptied event" || no "uninstall drops the emptied event" "the key is still there"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
