#!/bin/bash
# UserPromptSubmit hook — hands Claude the guidance the Stop hooks in this
# package queued about its previous reply.
#
# Background. A Stop hook has no way to tell Claude something without telling
# the user too: Claude Code 2.1.312 prints a Stop hook's additionalContext as
# "Stop hook feedback: …" and its block reason as "Stop hook error: …", in
# full, under "Ran N stop hooks". The user wants only the one-line
# systemMessage. So check-write-handoff.sh and check-bare-references.sh print
# that line and write their guidance to a file named after the session; this
# hook reads it back on the user's next prompt, as additionalContext, which
# Claude Code does not display.
#
# The queue is ~/.claude/claude-guard-hooks/pending/<session_id>.<hook>.txt.
# A file is deleted once delivered; any left by a session that ended before
# the user wrote again is deleted after a day.

JQ=$(command -v jq || echo /usr/bin/jq)
[ -x "$JQ" ] || exit 0

dir="${CLAUDE_DIR:-$HOME/.claude}/claude-guard-hooks/pending"
[ -d "$dir" ] || exit 0
find "$dir" -name '*.txt' -mtime +1 -delete 2>/dev/null

sid=$("$JQ" -r '.session_id // empty' | tr -cd 'A-Za-z0-9_-')
[ -n "$sid" ] || exit 0

guidance=""
for f in "$dir/$sid".*.txt; do
  [ -f "$f" ] || continue
  guidance="$guidance${guidance:+

}$(cat "$f")"
  rm -f "$f"
done
[ -n "$guidance" ] || exit 0

"$JQ" -n --arg g "$guidance" '{
  hookSpecificOutput: { hookEventName: "UserPromptSubmit", additionalContext: $g }
}'
exit 0
