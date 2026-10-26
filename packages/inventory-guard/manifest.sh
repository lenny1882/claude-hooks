# What this package installs. Sourced by install.sh and uninstall.sh.
#
# This is the hook variant: one script in ~/.claude/hooks, registered in
# settings.json. Edit the parts marked EDIT; the machinery around it does not
# need changing.

PKG="inventory-guard"

# Every settings entry and installed file this package owns is found by this
# substring, and by the basename of each script in FILES. The script is not
# named after the package — its installed name predates it — so it is the
# basename that finds its entry on reinstall and uninstall.
OWNS="inventory-guard"

# "<path in this repo>:<where it goes>". CLAUDE_DIR is ~/.claude unless
# overridden, which is how the tests run against a throwaway directory.
FILES=(
  "hooks/inventory-check.sh:$CLAUDE_DIR/hooks/inventory-check.sh"
)

# Other directories uninstall.sh removes. Not for state: uninstall.sh already
# removes the package's state (~/.claude/inventory-guard/, unless --keep-state) and
# ~/.local/share/inventory-guard. See reference/layout.md.
STATE_DIRS=()

# One Stop entry, no matcher. The command keeps the
# "bash ~/.claude/hooks/<script>" form the pre-kit installer wrote, so
# reinstalling over that install replaces its entry in place.
settings_merge() {
  jq '
    .hooks //= {}
    | .hooks.Stop = ((.hooks.Stop // []) + [
        { hooks: [{ type: "command",
                    command: "bash ~/.claude/hooks/inventory-check.sh",
                    statusMessage: "Checking the inventory…" }] }
      ])
  '
}

REGISTRATIONS=(
  "Stop -> inventory-check.sh, watching ${CLAUDE_INVENTORY:-$HOME/claude-sandbox/INVENTORY.md}"
)

# Give the hook an unlisted hook in a throwaway HOME and an empty inventory,
# and confirm it blocks the turn and names what is missing. A hook that stopped
# blocking would install cleanly and let the inventory drift unnoticed.
verify_probe() {
  local t rc
  t=$(mktemp -d) || return 1
  mkdir -p "$t/.claude/hooks"
  : > "$t/.claude/hooks/probe-unlisted.sh"
  : > "$t/INVENTORY.md"
  printf '%s' '{"hook_event_name":"Stop","session_id":"probe","stop_hook_active":false}' \
    | HOME="$t" CLAUDE_INVENTORY="$t/INVENTORY.md" bash "$CLAUDE_DIR/hooks/inventory-check.sh" \
      >"$t/out" 2>/dev/null
  rc=$?
  jq -se '.[0].hookSpecificOutput.additionalContext // "" | test("probe-unlisted.sh")' "$t/out" >/dev/null 2>&1; local named=$?
  rm -rf "$t"
  [ "$rc" = 0 ] && [ "$named" = 0 ]
}
