# What this package installs. Sourced by install.sh and uninstall.sh.
#
# This is the hook variant: one script in ~/.claude/hooks, registered in
# settings.json. Edit the parts marked EDIT; the machinery around it does not
# need changing.

PKG="handoff-gate"

# Every settings entry and installed file this package owns is found by this
# substring. It must appear in the command string of every entry you register,
# which it will if the script is named after the package.
OWNS="handoff-gate"

# "<path in this repo>:<where it goes>". CLAUDE_DIR is ~/.claude unless
# overridden, which is how the tests run against a throwaway directory.
FILES=(
  "hooks/handoff-gate.sh:$CLAUDE_DIR/hooks/handoff-gate.sh"
)

# Other directories uninstall.sh removes. Not for state: uninstall.sh already
# removes the package's state (~/.claude/handoff-gate/, unless --keep-state) and
# ~/.local/share/handoff-gate. See reference/layout.md.
STATE_DIRS=()

# EDIT: the settings.json entries. Reads the current settings on stdin and
# writes the new ones on stdout. strip_ours has already removed this package's
# previous entries, so this only has to add.
#
# Every event name is valid here — PreToolUse, PostToolUse, SessionStart, Stop,
# PreCompact, and the rest. Matchers are per-event: a tool name for PreToolUse,
# startup/resume/clear for SessionStart, manual/auto for PreCompact,
# a command name for UserPromptExpansion.
#
# A slash command the user typed never becomes a Skill tool call, so a
# PreToolUse matcher on Skill sees only the ones Claude starts itself. Catching
# both means registering the same script on UserPromptExpansion as well, and
# leaving the matcher out so it fires on every command — a matcher that misses
# fails silently. Add this branch alongside the one below when that is what the
# hook is for:
#
#     | .hooks.UserPromptExpansion = ((.hooks.UserPromptExpansion // []) + [
#         { hooks: [{ type: "command", command: $cmd }] }
#       ])
#
# Its exit 2 goes to the user, not to Claude — see reference/hook-events.md.
settings_merge() {
  jq --arg cmd "~/.claude/hooks/$PKG.sh" '
    .hooks //= {}
    | .hooks.PreToolUse = ((.hooks.PreToolUse // []) + [
        { matcher: "Bash",
          hooks: [{ type: "command", command: $cmd }] }
      ])
  '
}

# EDIT: one line per registration, printed by install.sh when it finishes.
REGISTRATIONS=(
  "PreToolUse (matcher: Bash)"
)

# EDIT, or delete. A live check that the thing actually works, run at the end
# of install.sh. Return 0 for pass. The reference packages feed their hook a
# payload it should refuse and confirm that it does — an installer that only
# checks the file exists will happily report success on a broken script.
verify_probe() {
  local out
  out=$(printf '{"tool_input":{"command":"true"}}' | "$CLAUDE_DIR/hooks/$PKG.sh" 2>/dev/null) || true
  [ -n "$out" ] || return 0   # a hook that stays silent on a normal call is fine
  printf '%s' "$out" | jq -e . >/dev/null 2>&1
}
