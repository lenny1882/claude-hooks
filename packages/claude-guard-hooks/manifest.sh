# What this package installs. Sourced by install.sh and uninstall.sh.
#
# This is the hook variant: one script in ~/.claude/hooks, registered in
# settings.json. Edit the parts marked EDIT; the machinery around it does not
# need changing.

PKG="claude-guard-hooks"

# Every settings entry and installed file this package owns is found by this
# substring, and by the basename of each script in FILES. The two scripts are
# not named after the package — their installed names predate it — so it is
# the basenames that find their entries on reinstall and uninstall.
OWNS="claude-guard-hooks"

# "<path in this repo>:<where it goes>". CLAUDE_DIR is ~/.claude unless
# overridden, which is how the tests run against a throwaway directory.
FILES=(
  "hooks/check-discuss-batch.sh:$CLAUDE_DIR/hooks/check-discuss-batch.sh"
  "hooks/gate-unsandboxed-bash.sh:$CLAUDE_DIR/hooks/gate-unsandboxed-bash.sh"
  "hooks/redirect-blocked-write.sh:$CLAUDE_DIR/hooks/redirect-blocked-write.sh"
  "hooks/check-write-handoff.sh:$CLAUDE_DIR/hooks/check-write-handoff.sh"
  "hooks/guard-generated-files.sh:$CLAUDE_DIR/hooks/guard-generated-files.sh"
  "hooks/guard-secret-files.sh:$CLAUDE_DIR/hooks/guard-secret-files.sh"
  "hooks/check-bare-references.sh:$CLAUDE_DIR/hooks/check-bare-references.sh"
)

# Other directories uninstall.sh removes. Not for state: uninstall.sh already
# removes the package's state (~/.claude/claude-guard-hooks/, unless --keep-state) and
# ~/.local/share/claude-guard-hooks. See reference/layout.md.
STATE_DIRS=()

# check-discuss-batch.sh is registered twice because there are two ways in:
# Claude calling the Skill tool, and the user typing the command, which never
# becomes a Skill call. UserPromptExpansion has no matcher on purpose — the
# name a plugin skill registers under is not worth betting on, and a matcher
# that misses fails silently. The script filters instead. See README.md.
#
# redirect-blocked-write.sh is registered on PostToolUse and PostToolUseFailure
# because a blocked write mid-pipeline exits 0 and only the first sees it, while
# a command that exits non-zero only reaches the second.
#
# Commands keep the "bash ~/.claude/hooks/<script>" form the pre-kit installer
# wrote, so reinstalling over that install replaces its entries in place.
#
# The first build of 1.3.1 (withdrawn 28 Oct 2026) shipped deliver-stop-guidance.sh on
# UserPromptSubmit; the rebuilt 1.3.1 dropped it.
# It is no longer in FILES, so the installer would not find its entry: this
# removes the entry, the script and its queue.
settings_merge() {
  if [ "${DRY:-0}" -ne 1 ]; then
    rm -f "$CLAUDE_DIR/hooks/deliver-stop-guidance.sh"
    rm -rf "$CLAUDE_DIR/claude-guard-hooks/pending"
  fi
  jq '
    def entry($s): { type: "command", command: ("bash ~/.claude/hooks/" + $s) };
    def rewake($s; $summary): entry($s) + { asyncRewake: true, rewakeSummary: $summary };
    .hooks //= {}
    | if .hooks.UserPromptSubmit then
        .hooks.UserPromptSubmit |= (map(.hooks |= map(select((.command // "") | contains("deliver-stop-guidance.sh") | not)))
                                    | map(select((.hooks | length) > 0)))
        | if .hooks.UserPromptSubmit == [] then del(.hooks.UserPromptSubmit) else . end
      else . end
    | .hooks.PreToolUse = ((.hooks.PreToolUse // []) + [
        { matcher: "Skill", hooks: [entry("check-discuss-batch.sh")] },
        { matcher: "Bash",  hooks: [entry("gate-unsandboxed-bash.sh")] },
        { matcher: "Edit|Write|MultiEdit|NotebookEdit|Bash", hooks: [entry("guard-generated-files.sh")] },
        { matcher: "Read|Bash", hooks: [entry("guard-secret-files.sh")] }
      ])
    | .hooks.UserPromptExpansion = ((.hooks.UserPromptExpansion // []) + [
        { hooks: [entry("check-discuss-batch.sh")] }
      ])
    | .hooks.PostToolUse = ((.hooks.PostToolUse // []) + [
        { matcher: "Bash", hooks: [entry("redirect-blocked-write.sh")] }
      ])
    | .hooks.PostToolUseFailure = ((.hooks.PostToolUseFailure // []) + [
        { matcher: "Bash", hooks: [entry("redirect-blocked-write.sh")] }
      ])
    | .hooks.Stop = ((.hooks.Stop // []) + [
        { hooks: [rewake("check-write-handoff.sh"; "Reply handed you a write Claude can do itself")] },
        { hooks: [rewake("check-bare-references.sh"; "Reply used an unexplained id")] }
      ])
  '
}

REGISTRATIONS=(
  "PreToolUse (matcher: Skill) -> check-discuss-batch.sh"
  "PreToolUse (matcher: Bash) -> gate-unsandboxed-bash.sh"
  "UserPromptExpansion (no matcher) -> check-discuss-batch.sh"
  "PostToolUse (matcher: Bash) -> redirect-blocked-write.sh"
  "PostToolUseFailure (matcher: Bash) -> redirect-blocked-write.sh"
  "Stop (no matcher, asyncRewake) -> check-write-handoff.sh"
  "PreToolUse (matcher: Edit|Write|MultiEdit|NotebookEdit|Bash) -> guard-generated-files.sh"
  "PreToolUse (matcher: Read|Bash) -> guard-secret-files.sh"
  "Stop (no matcher, asyncRewake) -> check-bare-references.sh"
)

# Feed each hook a call it must refuse and confirm it does. The PreToolUse ones
# deny rather than ask; the Stop ones exit 2 with guidance on stderr. A hook that stopped
# doing either would install cleanly and do nothing.
verify_probe() {
  local out
  out=$(printf '%s' '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"ls","dangerouslyDisableSandbox":true}}' \
    | bash "$CLAUDE_DIR/hooks/gate-unsandboxed-bash.sh" 2>/dev/null) || return 1
  printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1 || return 1
  out=$(printf '%s' '{"hook_event_name":"PreToolUse","tool_name":"Skill","tool_input":{"skill":"gsd:discuss-phase","args":"3"}}' \
    | bash "$CLAUDE_DIR/hooks/check-discuss-batch.sh" 2>/dev/null) || return 1
  printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1 || return 1
  printf '%s' '{"hook_event_name":"PostToolUseFailure","tool_name":"Bash","error":"cp: cannot create regular file '"'"'/x'"'"': Read-only file system"}' \
    | bash "$CLAUDE_DIR/hooks/redirect-blocked-write.sh" 2>/dev/null \
    | jq -se '.[0].hookSpecificOutput.additionalContext' >/dev/null 2>&1 || return 1
  printf '%s' '{"hook_event_name":"Stop","stop_hook_active":false,"last_assistant_message":"~/x is read-only from this session."}' \
    | bash "$CLAUDE_DIR/hooks/check-write-handoff.sh" >/dev/null 2>&1; [ $? = 2 ] || return 1
  out=$(printf '%s' '{"hook_event_name":"PreToolUse","tool_name":"Edit","tool_input":{"file_path":"/r/lib/router/routes.gr.dart"}}' \
    | bash "$CLAUDE_DIR/hooks/guard-generated-files.sh" 2>/dev/null) || return 1
  printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1 || return 1
  out=$(printf '%s' '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"cat .env"}}' \
    | bash "$CLAUDE_DIR/hooks/guard-secret-files.sh" 2>/dev/null) || return 1
  printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1 || return 1
  printf '%s' '{"hook_event_name":"Stop","stop_hook_active":false,"last_assistant_message":"F6 is still open."}' \
    | bash "$CLAUDE_DIR/hooks/check-bare-references.sh" >/dev/null 2>&1; [ $? = 2 ] || return 1
}
