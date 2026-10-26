#!/usr/bin/env bash
# PreCompact handoff gate.
#
# Installed twice against the PreCompact "manual" matcher:
#   gate  (synchronous)  - cancels /compact when the handoff is out of date
#   wake  (asyncRewake)  - wakes this session and asks it to write the handoff
#
# Escape hatches, in order of bluntness:
#   /compact skip handoff     one-off, passes straight through
#   .nohandoff in the project  this directory never asks again
#
# Set FALLBACK=1 to have the wake side write the handoff itself, with a
# separate headless Claude, if the session hasn't done it within GRACE seconds.
set -uo pipefail

FALLBACK=0
GRACE=120
FALLBACK_MODEL=claude-sonnet-5

MODE="${1:-gate}"
# GNU and BSD stat disagree; try both so this runs on macOS too.
mtime(){ stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0; }
STATE="$HOME/.claude/handoff-gate"
LOG="$STATE/log"
mkdir -p "$STATE"

started=$(date +%s)
input=$(cat)
sid=$(jq -r '.session_id // "nosession"' <<<"$input" 2>/dev/null || echo nosession)
cwd=$(jq -r '.cwd // empty'             <<<"$input" 2>/dev/null)
custom=$(jq -r '.custom_instructions // empty' <<<"$input" 2>/dev/null)
transcript=$(jq -r '.transcript_path // empty' <<<"$input" 2>/dev/null)
[ -n "$cwd" ] && [ -d "$cwd" ] || cwd="$PWD"
cd "$cwd" || exit 0

# --- opt-outs -------------------------------------------------------------
shopt -s nocasematch
if [[ "$custom" == *"skip handoff"* || "$custom" == *nohandoff* ]]; then exit 0; fi
shopt -u nocasematch

root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || root="$cwd"
[ -e "$root/.nohandoff" ] && exit 0
[ -e "$cwd/.nohandoff" ]  && exit 0

# --- where the handoff lives ---------------------------------------------
if [ -d "$root/.planning" ]; then
  target="$root/.continue-here.md"
  advice="run /gsd:pause-work, which writes $target and commits it"
else
  target="$root/HANDOFF.md"
  advice="write or update $target"
fi

decision="$STATE/${sid}.decision"
marker="$STATE/${sid}.marker"

# =========================================================================
# wake side: wait for the gate's verdict, then push the job into the session
# =========================================================================
if [ "$MODE" = wake ]; then
  for _ in $(seq 1 20); do
    if [ -f "$decision" ] && [ "$(mtime "$decision")" -ge "$((started - 2))" ]; then
      break
    fi
    sleep 0.5
  done
  [ -f "$decision" ] || exit 0
  [ "$(cat "$decision" 2>/dev/null)" = block ] || exit 0

  if [ "$FALLBACK" = 1 ]; then
    (
      sleep "$GRACE"
      if [ ! -f "$target" ] || [ ! "$target" -nt "$marker" ]; then
        tmp=$(mktemp)
        # Last stretch of actual conversation, tool output stripped: the raw
        # transcript runs to megabytes and will not fit in a context window.
        tail -n 400 "$transcript" 2>/dev/null \
          | jq -r 'select(.type=="user" or .type=="assistant")
                   | .message.content
                   | if type=="array" then map(select(.type=="text").text) | join("\n") else . end
                   | select(. != null and . != "")' 2>/dev/null \
          | tail -c 400000 > "$tmp"
        CLAUDE_HANDOFF_FALLBACK=1 claude -p --model "$FALLBACK_MODEL" \
          "Below is the tail of a Claude Code session in $root. Append a dated
section to $target describing where the work stands: what is being worked on and
why, decisions taken and rejected, what is unfinished, and anything that would
mislead someone reading the code cold. Prose, not a chronology. Do not rewrite or
delete anything already in the file.

$(cat "$tmp")" >>"$LOG" 2>&1
        rm -f "$tmp"
      fi
    ) &
  fi

  cat >&2 <<EOF
Before this conversation is compacted, $advice.

Cover where the work actually stands: what is in progress and why, decisions
taken and the ones rejected, what is unfinished, and anything a reader coming to
this cold would get wrong. Prose that is worth reading, not a list of what
happened. Keep what is already in the file unless it is now wrong.

Then tell the user it is ready and that /compact will go through now.
EOF
  exit 2
fi

# =========================================================================
# gate side: allow or cancel the compaction
# =========================================================================
if [ -f "$target" ] && [ -f "$marker" ] && [ "$target" -nt "$marker" ]; then
  printf allow > "$decision"
  rm -f "$marker"
  # stdout here becomes the compaction instructions
  cat <<EOF
A handoff for this work has just been written to $target. Keep the summary
consistent with it, and preserve: the task in progress and its current state,
file paths touched, decisions taken and rejected, unfinished work, and any
correction the user made to an earlier assumption.
EOF
  exit 0
fi

printf block > "$decision"
: > "$marker"
if [ -f "$target" ]; then
  cat >&2 <<EOF
$(basename "$target") has not been updated since this session's work. Claude has
been asked to $advice — when it says it is done, run /compact again.
Skip this once with: /compact skip handoff
EOF
else
  cat >&2 <<EOF
No handoff exists for this project yet. Claude has been asked to $advice —
when it says it is done, run /compact again.
Skip this once with: /compact skip handoff   Never ask here: touch .nohandoff
EOF
fi
exit 2
