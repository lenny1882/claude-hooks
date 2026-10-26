# What this package installs. Sourced by install.sh and uninstall.sh.
#
# This is the hook variant: one script in ~/.claude/hooks, registered in
# settings.json. Edit the parts marked EDIT; the machinery around it does not
# need changing.

PKG="handoff-gate"

# Every settings entry and installed file this package owns is found by this
# substring, and by the basename of each script in FILES. The script is not
# named after the package — its installed name predates it — so it is the
# basename that finds its entries on reinstall and uninstall.
OWNS="handoff-gate"

# "<path in this repo>:<where it goes>". CLAUDE_DIR is ~/.claude unless
# overridden, which is how the tests run against a throwaway directory.
FILES=(
  "hooks/precompact-handoff.sh:$CLAUDE_DIR/hooks/precompact-handoff.sh"
)

# Other directories uninstall.sh removes. Not for state: uninstall.sh already
# removes the package's state (~/.claude/handoff-gate/, unless --keep-state) and
# ~/.local/share/handoff-gate. See reference/layout.md.
STATE_DIRS=()

# One PreCompact entry on the "manual" matcher, holding the same script twice.
# "gate" runs synchronously and decides; "wake" is backgrounded by asyncRewake
# and is what hands the job to the running session. asyncRewake,
# rewakeMessage and rewakeSummary are undocumented — see README.md. The
# commands are the ones the pre-kit installer wrote, so reinstalling over that
# install replaces its entries in place.
settings_merge() {
  jq '
    .hooks //= {}
    | .hooks.PreCompact = ((.hooks.PreCompact // []) + [
        { matcher: "manual",
          hooks: [
            { type: "command",
              command: "~/.claude/hooks/precompact-handoff.sh gate",
              statusMessage: "Checking the handoff…" },
            { type: "command",
              command: "~/.claude/hooks/precompact-handoff.sh wake",
              asyncRewake: true,
              rewakeMessage: "Compaction was cancelled until the handoff is up to date.",
              rewakeSummary: "Handoff needed before compacting" }
          ] }
      ])
  '
}

REGISTRATIONS=(
  "PreCompact (matcher: manual) -> precompact-handoff.sh gate"
  "PreCompact (matcher: manual, asyncRewake) -> precompact-handoff.sh wake"
)

# Run the gate against a throwaway HOME and project with no handoff, and confirm
# it cancels the compaction; then confirm "skip handoff" lets it through. A gate
# that stopped cancelling would install cleanly and let every /compact through.
verify_probe() {
  local t rc1 rc2
  t=$(mktemp -d) || return 1
  mkdir -p "$t/home/.claude" "$t/proj"
  jq -nc --arg c "$t/proj" '{session_id:"probe",cwd:$c,hook_event_name:"PreCompact",trigger:"manual"}' \
    | HOME="$t/home" "$CLAUDE_DIR/hooks/precompact-handoff.sh" gate >/dev/null 2>&1
  rc1=$?
  jq -nc --arg c "$t/proj" '{session_id:"probe",cwd:$c,hook_event_name:"PreCompact",trigger:"manual",custom_instructions:"skip handoff"}' \
    | HOME="$t/home" "$CLAUDE_DIR/hooks/precompact-handoff.sh" gate >/dev/null 2>&1
  rc2=$?
  rm -rf "$t"
  [ "$rc1" = 2 ] && [ "$rc2" = 0 ]
}
