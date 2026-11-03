#!/bin/bash
# UserPromptSubmit hook — adds an instruction to Claude's context alongside each
# typed message: read it against the work in progress before replying. It only
# adds context; it never blocks a message.
#
# Background. On 2 Nov 2026 the user was going through decisions one at a time
# and asked for the reason behind each. Claude read that as a new request and
# gave all nine at once. A transcript scan from 5 Oct to 3 Nov 2026 found 11
# corrections of this kind. A rule in CLAUDE.md doesn't reach them: Claude
# doesn't think it has misread anything, so no rule triggers.
#
# Every message, not only short ones. The 2 Nov message is 35 words; a 30-word
# limit would have missed the case that raised this.
#
# Slash commands are skipped: they carry their own instructions. A path such as
# `/tmp/x is empty` is a message, so the first word must have no second slash.
#
# This event also fires for scheduled tasks, /loop iterations, background
# subagent reports and messages from other sessions. The ones wrapped in a
# <task-notification> or <agent-message> tag are skipped: nobody typed them. The
# docs don't give the exact payload for these, so the tag check is a best guess
# from how they appear in transcripts. A miss costs about 100 words of context.

command -v jq >/dev/null || exit 0   # fail open

input=$(cat)
prompt=$(printf '%s' "$input" | jq -r '.prompt // empty')
[ -n "$prompt" ] || exit 0
first=$(printf '%s' "$prompt" | head -n 1)
printf '%s' "$first" | grep -qE '^[[:space:]]*/[^/[:space:]]+([[:space:]]|$)' && exit 0
printf '%s' "$first" | grep -qE '^[[:space:]]*<(task-notification|agent-message)[ >]' && exit 0

jq -nc --arg c "Do this check silently and leave it out of the reply. Before replying, work out what the conversation is in the middle of: the item, step or mode (one at a time, a draft under review, a test running). Read this message as a change to that work, not as a new task: which item it applies to, and whether it changes the current step, the items to come or the whole task. Keep the current mode and scope unless the message says to leave them. If two readings lead to different replies and the thread doesn't settle which, ask which in one line." \
  '{ hookSpecificOutput: { hookEventName: "UserPromptSubmit", additionalContext: $c } }'
