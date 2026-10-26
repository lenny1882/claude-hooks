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
jq -e '[.. | .command? // empty] | any(test("check-discuss-batch\\.sh|gate-unsandboxed-bash\\.sh|redirect-blocked-write\\.sh|check-write-handoff\\.sh|guard-generated-files\\.sh|guard-secret-files\\.sh|check-bare-references\\.sh"))' \
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

echo "redirect-blocked-write"
# PostToolUse: the error sits in stdout because the command merged stderr.
pt(){ jq -nc --arg o "$1" '{hook_event_name:"PostToolUse",tool_name:"Bash",
      tool_input:{command:"x"},tool_response:{stdout:$o,stderr:"",interrupted:false}}'; }
pf(){ jq -nc --arg e "$1" '{hook_event_name:"PostToolUseFailure",tool_name:"Bash",
      tool_input:{command:"x"},error:$e}'; }
for e in "cp: cannot create regular file '/home/u/claude-sandbox/M.md': Read-only file system" \
         "/bin/bash: MEMORY.md: Read-only file system" \
         "OSError: [Errno 30] Read-only file system: 'p.md'" \
         "npm error code EROFS" \
         "error: could not lock config file .git/config: File exists" \
         "fatal: Unable to create '/r/.git/index.lock': Read-only file system"; do
  call redirect-blocked-write.sh "$(pf "Exit code 1
$e")"
  blocked && ok "failure: ${e:0:50}" || no "failure: ${e:0:50}" "rc=$rc"
done
call redirect-blocked-write.sh "$(pt "== a
tee: /tmp/x.log: Read-only file system
syntax ok")"
blocked && ok "a blocked write mid-pipeline that exited 0 is caught" || no "a blocked write mid-pipeline that exited 0 is caught" "rc=$rc"
grep -q "Write or Edit" "$TMP/err" && ok "the message names Write and Edit" || no "the message names Write and Edit" "$(cat "$TMP/err")"
grep -q "Read-only file system" "$TMP/err" && ok "the message quotes the error line" || no "the message quotes the error line" "$(cat "$TMP/err")"
for e in '**"Read-only file system" names one path, not a disk.**' \
         "gave \"Read-only file system\" on touch" \
         "git@github.com: Permission denied (publickey)." \
         "warning: unable to access '/r/.gitmodules': Permission denied" \
         "rm: cannot remove 'x': Device or resource busy"; do
  call redirect-blocked-write.sh "$(pt "$e")"
  [ "$rc" = 0 ] && ok "ignored: ${e:0:50}" || no "ignored: ${e:0:50}" "rc=$rc"
done
call redirect-blocked-write.sh "$(jq -nc '{hook_event_name:"PostToolUse",tool_name:"Bash",tool_response:"plain string output"}')"
[ "$rc" = 0 ] && ok "a string tool_response is tolerated" || no "a string tool_response is tolerated" "rc=$rc"

echo "check-write-handoff"
st(){ jq -nc --arg m "$1" --argjson a "${2:-false}" '{hook_event_name:"Stop",stop_hook_active:$a,last_assistant_message:$m}'; }
# The four replies the user corrected on 26 Oct 2026, cut down.
for m in "The updated MIGRATION.md is ready, but I couldn't save it over the original: ~/claude-sandbox is read-only from this session." \
         "To put it in place, type:
\`\`\`
! cp /tmp/s/MIGRATION.md ~/claude-sandbox/MIGRATION.md
\`\`\`" \
         "You can add it yourself from this prompt:
\`\`\`
! git -C /r remote add origin https://github.com/u/r.git
\`\`\`" \
         "Building the app is blocked. The Bash sandbox won't let me write to it." \
         "The sandbox can't write to ~/claude-sandbox." \
         "Run:
! echo '- [x](x.md)' >> ~/.claude/projects/p/memory/MEMORY.md"; do
  call check-write-handoff.sh "$(st "$m")"
  blocked && ok "blocks: $(printf '%s' "$m" | tr '\n' ' ' | cut -c1-48)" || no "blocks: $(printf '%s' "$m" | tr '\n' ' ' | cut -c1-48)" "rc=$rc"
done
grep -q "Write or Edit" "$TMP/err" && ok "the message names Write and Edit" || no "the message names Write and Edit" "$(cat "$TMP/err")"
for m in "\`MIGRATION.md\` is updated. Bash's \`cp\` got \"Read-only file system\", but the Write tool wrote the file directly." \
         "Bash's sandbox blocks writes to ~/.ssh, so push from your prompt:
! git push --atomic origin main release/x-v1.x x-v1.2.0" \
         "Bash's sandbox blocks deleting it:
! rm ~/.claude/projects/p/memory/one-liner-commands.md" \
         "! cd /r && ./gradlew assembleDebug 2>&1 | tail" \
         "Bash's sandbox blocks writes under ~/.claude/projects:
! xargs -d '\\n' rm -v -- < /tmp/list.txt > /tmp/rm.log 2>&1; rm -rv ~/.claude/memory >> /tmp/rm.log 2>&1" \
         "! ./scripts/test.sh up > /tmp/test-up.log 2>&1" \
         "The hook blocks replies that say \"can't write\" next to a \`! cp\`."; do
  call check-write-handoff.sh "$(st "$m")"
  [ "$rc" = 0 ] && ok "allows: $(printf '%s' "$m" | tr '\n' ' ' | cut -c1-48)" || no "allows: $(printf '%s' "$m" | tr '\n' ' ' | cut -c1-48)" "rc=$rc $(cat "$TMP/err")"
done
call check-write-handoff.sh "$(st "I can't write to it." true)"
[ "$rc" = 0 ] && ok "stop_hook_active lets the turn end" || no "stop_hook_active lets the turn end" "rc=$rc"
# No last_assistant_message: read the reply from the transcript, and only the
# part after the user's last prompt.
{ jq -nc '{type:"assistant",message:{content:[{type:"text",text:"Earlier: ~/x is read-only from this session."}]}}'
  jq -nc '{type:"user",message:{content:"next"}}'
  jq -nc '{type:"assistant",message:{content:[{type:"tool_use",name:"Write",input:{}}]}}'
  jq -nc '{type:"user",message:{content:[{type:"tool_result",content:"ok"}]}}'
  jq -nc '{type:"assistant",message:{content:[{type:"text",text:"Written with the Write tool."}]}}'
} > "$TMP/t.jsonl"
call check-write-handoff.sh "$(jq -nc --arg t "$TMP/t.jsonl" '{hook_event_name:"Stop",stop_hook_active:false,transcript_path:$t}')"
[ "$rc" = 0 ] && ok "transcript fallback reads only the current reply" || no "transcript fallback reads only the current reply" "rc=$rc"
jq -nc '{type:"assistant",message:{content:[{type:"text",text:"I couldn'"'"'t write the file."}]}}' >> "$TMP/t.jsonl"
call check-write-handoff.sh "$(jq -nc --arg t "$TMP/t.jsonl" '{hook_event_name:"Stop",stop_hook_active:false,transcript_path:$t}')"
blocked && ok "transcript fallback catches the claim" || no "transcript fallback catches the claim" "rc=$rc"

echo "guard-generated-files"
ed(){ jq -nc --arg t "$1" --arg p "$2" --arg c "${3:-}" '{hook_event_name:"PreToolUse",tool_name:$t,
      tool_input:{file_path:$p,content:$c,old_string:"a",new_string:"b"}}'; }
bs(){ jq -nc --arg c "$1" '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c}}'; }
for p in /r/lib/router/routes.gr.dart /r/lib/m.g.dart /r/lib/m.freezed.dart /r/test/x.mocks.dart \
         /r/pubspec.lock /r/ios/Podfile.lock /r/go.sum /r/package-lock.json /r/api/v1.pb.go; do
  call guard-generated-files.sh "$(ed Edit "$p")"
  denied && ok "Edit denied: ${p##*/}" || no "Edit denied: ${p##*/}" "$(cat "$TMP/out")"
done
printf '// Code generated by openapi-generator. DO NOT EDIT.\npackage api\n' > "$TMP/api.go"
call guard-generated-files.sh "$(ed Edit "$TMP/api.go")"
denied && ok "Edit denied: a file whose header says DO NOT EDIT" || no "Edit denied: a file whose header says DO NOT EDIT" "$(cat "$TMP/out")"
call guard-generated-files.sh "$(ed Write /r/lib/new.dart "// GENERATED CODE - DO NOT MODIFY BY HAND
part of x;")"
denied && ok "Write denied: content that claims to be generated" || no "Write denied: content that claims to be generated" "$(cat "$TMP/out")"
grep -q build_runner "$TMP/out" && ok "the refusal names a generator to run" || no "the refusal names a generator to run" "$(cat "$TMP/out")"
for p in /r/lib/router/routes.dart /r/lib/glob.dart /r/pubspec.yaml /r/go.mod "$TMP/out"; do
  call guard-generated-files.sh "$(ed Edit "$p")"
  denied && no "Edit allowed: ${p##*/}" "denied" || ok "Edit allowed: ${p##*/}"
done
for c in "sed -i 's/a/b/' lib/router/routes.gr.dart" "perl -pi -e 's/a/b/' go.sum" \
         "echo x >> pubspec.lock" "printf y | tee lib/m.g.dart"; do
  call guard-generated-files.sh "$(bs "$c")"
  denied && ok "Bash denied: $c" || no "Bash denied: $c" "$(cat "$TMP/out")"
done
for c in "dart run build_runner build --delete-conflicting-outputs" "go mod tidy && git diff --stat go.sum" \
         "cat lib/router/routes.gr.dart | head" "git checkout -- pubspec.lock" "ls *.g.dart" "sed -i 's/a/b/' lib/x.dart"; do
  call guard-generated-files.sh "$(bs "$c")"
  denied && no "Bash allowed: $c" "denied" || ok "Bash allowed: $c"
done

echo "guard-secret-files"
rd(){ jq -nc --arg p "$1" '{hook_event_name:"PreToolUse",tool_name:"Read",tool_input:{file_path:$p}}'; }
for p in /r/.env /r/.env.local "/r/bruno/MESH Data/.env" /home/u/.netrc /home/u/.aws/credentials \
         /home/u/.ssh/id_ed25519 "/r/bruno/MESH Data/environments/Dev.bru"; do
  call guard-secret-files.sh "$(rd "$p")"
  denied && ok "Read denied: $p" || no "Read denied: $p" "$(cat "$TMP/out")"
done
for p in /r/.env.example /r/.env.sample /r/src/credentials.go /home/u/.ssh/id_ed25519.pub /r/environment.ts; do
  call guard-secret-files.sh "$(rd "$p")"
  denied && no "Read allowed: $p" "denied" || ok "Read allowed: $p"
done
for c in "cat .env" "head -5 services/v1/admin/.env.local" "cat ~/.netrc" "grep AWS .env" \
         "diff services/a/.env.local services/b/.env.local" "awk -F= '{print \$2}' .env" "X=1 cat .env" \
         "less ~/.aws/credentials" "ls && cat .env | wc -l"; do
  call guard-secret-files.sh "$(bs "$c")"
  denied && ok "Bash denied: $c" || no "Bash denied: $c" "$(cat "$TMP/out")"
done
grep -q "grep -oE" "$TMP/out" && ok "the refusal gives the key-names command" || no "the refusal gives the key-names command" "$(cat "$TMP/out")"
for c in "grep -oE '^[A-Za-z_][A-Za-z0-9_]*' .env" "cut -d= -f1 .env" "cmp a/.env.local b/.env.local && echo same" \
         "cp .env.example .env" "diff -q a/.env b/.env" "grep -c AWS .env" "git check-ignore -v .env" \
         "source .env && go test ./..." "curl -n https://api.bitbucket.org/2.0/x" "cat .env.example" "cat README.md"; do
  call guard-secret-files.sh "$(bs "$c")"
  denied && no "Bash allowed: $c" "denied" || ok "Bash allowed: $c"
done

echo "check-bare-references"
for m in "F6 is still open, and 1b needs your answer." \
         "Recorded 1a and 2c. Next is the location question." \
         "D-18 still holds after the change." \
         "This covers ASGN-06 and CHAT-01." \
         "Done. F12 can go next." \
         "F6 is still open."; do
  call check-bare-references.sh "$(st "$m")"
  blocked && ok "blocks: $m" || no "blocks: $m" "rc=$rc"
done
grep -q "plain words" "$TMP/err" && ok "the message says what to do" || no "the message says what to do" "$(cat "$TMP/err")"
for m in "F12 (adding the nine memory files to their indexes) is done." \
         "**F17.** Generated-files hook: built and tested." \
         "D-18 is the rule that a deleted location sends the user to user select; it still holds." \
         "The bare-reference hook (F18) is built." \
         "1b: keep the old rows and read both forms. Recorded." \
         "Built it.

⎸ F11. Fix the EROFS false positive in redirect-blocked-write.sh." \
         "HBS-53 and HBD20-1801 are both deployed to dev." \
         "Run \`git log F6..main\` to see them." \
         "Commit 4b71a03b and session 1cf3ff3c, both on a 3d model."; do
  call check-bare-references.sh "$(st "$m")"
  [ "$rc" = 0 ] && ok "allows: $(printf '%s' "$m" | tr '\n' ' ' | cut -c1-50)" || no "allows: $(printf '%s' "$m" | tr '\n' ' ' | cut -c1-50)" "rc=$rc $(cat "$TMP/err")"
done
call check-bare-references.sh "$(st "F6 is open." true)"
[ "$rc" = 0 ] && ok "stop_hook_active lets the turn end" || no "stop_hook_active lets the turn end" "rc=$rc"

echo "installer — beside claude-branch-guard"
cat > "$CLAUDE_DIR/settings.json" <<'JSON'
{"model":"Opus","hooks":{"PreToolUse":[{"matcher":"Skill","hooks":[
  {"type":"command","command":"~/.claude/hooks/check-branch-naming.sh"}]}]}}
JSON
count(){ jq "[.hooks[$1][]?.hooks[]] | length" "$CLAUDE_DIR/settings.json"; }

"$REPO/install.sh" --link --yes >/dev/null 2>&1
[ "$(count '"PreToolUse"')" = 5 ] && ok "adds its four PreToolUse hooks without dropping the existing one" \
  || no "adds its four PreToolUse hooks without dropping the existing one" "got $(count '"PreToolUse"')"
[ "$(count '"UserPromptExpansion"')" = 1 ] && ok "registers the typed-command hook" \
  || no "registers the typed-command hook" "got $(count '"UserPromptExpansion"')"
[ "$(count '"Stop"')" = 2 ] && ok "registers the two Stop hooks" || no "registers the two Stop hooks" "got $(count '"Stop"')"
for ev in PostToolUse PostToolUseFailure; do
  [ "$(count "\"$ev\"")" = 1 ] && ok "registers the $ev hook" || no "registers the $ev hook" "got $(count "\"$ev\"")"
done
jq -e '.hooks.UserPromptExpansion[0] | has("matcher") | not' "$CLAUDE_DIR/settings.json" >/dev/null \
  && ok "the typed-command hook has no matcher" || no "the typed-command hook has no matcher" "it has one"
jq -e '[.hooks.PreToolUse[].hooks[].command] | any(contains("check-branch-naming"))' \
  "$CLAUDE_DIR/settings.json" >/dev/null \
  && ok "claude-branch-guard's hook survives" || no "claude-branch-guard's hook survives" "it was removed"

"$REPO/install.sh" --link --yes >/dev/null 2>&1
[ "$(count '"PreToolUse"')" = 5 ] && [ "$(count '"UserPromptExpansion"')" = 1 ] \
  && ok "reinstalling does not duplicate" \
  || no "reinstalling does not duplicate" "got $(count '"PreToolUse"') and $(count '"UserPromptExpansion"')"

"$REPO/uninstall.sh" --yes >/dev/null 2>&1
[ "$(count '"PreToolUse"')" = 1 ] && ok "uninstall removes only its own" || no "uninstall removes only its own" "got $(count '"PreToolUse"')"
jq -e '.hooks | has("UserPromptExpansion") | not' "$CLAUDE_DIR/settings.json" >/dev/null \
  && ok "uninstall drops the emptied event" || no "uninstall drops the emptied event" "the key is still there"
jq -e '.hooks | (has("PostToolUse") or has("PostToolUseFailure") or has("Stop")) | not' "$CLAUDE_DIR/settings.json" >/dev/null \
  && ok "uninstall drops the new events too" || no "uninstall drops the new events too" "$(jq -c .hooks "$CLAUDE_DIR/settings.json")"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
