#!/usr/bin/env bash
# Stop hook — refuses to let a turn end while something is installed into the
# Claude config that INVENTORY.md does not mention.
#
# The point is that the record maintains itself. Anything dropped into
# ~/.claude/hooks, ~/.claude/skills, ~/.claude/bin or ~/.local/bin/claude-* is
# compared against the inventory by name; anything unlisted blocks the turn with
# an instruction to write it down.
#
# Exit 2 on a Stop hook feeds stderr back to the model and stops the turn
# ending. Two guards against nagging: stop_hook_active is honoured, as the
# harness requires, and each session is told at most once.
#
#   INVENTORY file   $CLAUDE_INVENTORY, default ~/claude-sandbox/INVENTORY.md
#   turn it off      touch ~/.claude/.no-inventory-check
set -uo pipefail

INVENTORY="${CLAUDE_INVENTORY:-$HOME/claude-sandbox/INVENTORY.md}"
STATE="$HOME/.claude/inventory-guard"

JQ=$(command -v jq) || exit 0     # no jq: fail open rather than block every turn
input=$(cat)

[ "$(printf '%s' "$input" | "$JQ" -r '.stop_hook_active // false')" = true ] && exit 0
[ -e "$HOME/.claude/.no-inventory-check" ] && exit 0
[ -f "$INVENTORY" ] || exit 0

sid=$(printf '%s' "$input" | "$JQ" -r '.session_id // "nosession"')
mkdir -p "$STATE"
find "$STATE" -type f -mtime +7 -delete 2>/dev/null
seen="$STATE/$sid.told"
[ -f "$seen" ] && exit 0

missing=()
note(){ grep -qF "$2" "$INVENTORY" 2>/dev/null || missing+=("$1"); }

for f in "$HOME"/.claude/hooks/*.sh; do
  [ -e "$f" ] || continue
  b=$(basename "$f")
  case "$b" in *.bak|*.bak-*) continue ;; esac
  note "hook: $b" "$b"
done
for d in "$HOME"/.claude/skills/*/; do
  [ -e "$d" ] || continue
  note "skill: $(basename "$d")" "$(basename "$d")"
done
for f in "$HOME"/.claude/bin/* "$HOME"/.local/bin/claude-*; do
  [ -f "$f" ] || continue
  b=$(basename "$f")
  [ "$b" = claude ] && continue
  note "command: $b" "$b"
done

[ ${#missing[@]} -eq 0 ] && exit 0

: > "$seen"
{
  echo "These are installed but not written down in $INVENTORY:"
  printf '  - %s\n' "${missing[@]}"
  echo
  echo "Add a row for each: what it is, where its source directory is (or that it"
  echo "has none yet), and whether it still needs packaging. Keep the existing"
  echo "format. Then carry on with whatever you were doing."
} >&2
exit 2
