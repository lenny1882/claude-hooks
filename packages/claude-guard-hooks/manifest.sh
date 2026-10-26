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
# Commands keep the "bash ~/.claude/hooks/<script>" form the pre-kit installer
# wrote, so reinstalling over that install replaces its entries in place.
settings_merge() {
  jq '
    def entry($s): { type: "command", command: ("bash ~/.claude/hooks/" + $s) };
    .hooks //= {}
    | .hooks.PreToolUse = ((.hooks.PreToolUse // []) + [
        { matcher: "Skill", hooks: [entry("check-discuss-batch.sh")] },
        { matcher: "Bash",  hooks: [entry("gate-unsandboxed-bash.sh")] }
      ])
    | .hooks.UserPromptExpansion = ((.hooks.UserPromptExpansion // []) + [
        { hooks: [entry("check-discuss-batch.sh")] }
      ])
  '
}

REGISTRATIONS=(
  "PreToolUse (matcher: Skill) -> check-discuss-batch.sh"
  "PreToolUse (matcher: Bash) -> gate-unsandboxed-bash.sh"
  "UserPromptExpansion (no matcher) -> check-discuss-batch.sh"
)

# Feed each hook a call it must refuse and confirm it does. Both deny rather
# than ask; a hook that stopped denying would install cleanly and do nothing.
verify_probe() {
  local out
  out=$(printf '%s' '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"ls","dangerouslyDisableSandbox":true}}' \
    | bash "$CLAUDE_DIR/hooks/gate-unsandboxed-bash.sh" 2>/dev/null) || return 1
  printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1 || return 1
  out=$(printf '%s' '{"hook_event_name":"PreToolUse","tool_name":"Skill","tool_input":{"skill":"gsd:discuss-phase","args":"3"}}' \
    | bash "$CLAUDE_DIR/hooks/check-discuss-batch.sh" 2>/dev/null) || return 1
  printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1
}
