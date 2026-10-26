#!/bin/bash
# Stop hook — when a reply ends by asking permission for a next step ("Shall I
# …?", "Do you want me to …?"), sends it back once to decide whether the step
# needs the user at all.
#
# Background. In the 28 Sep – 26 Oct 2026 sessions the user asked "why have
# you stopped to ask?" or "then do it" in a dozen sessions over five projects.
# The memory meant to stop it (finish_the_task_dont_ask_about_steps,
# hugoboss-flutter-runner) was never added to its project's index, so it was
# never loaded.
#
# The other extreme is the reason this is a nudge and not a rule. The user does
# not want to pull Claude back and revert a pile of changes made because a hook
# said "stop asking". So the message gives both directions, and the questions
# that must be asked pass straight through without a block:
#  - a question that names an outward-facing or hard-to-undo step (push, post,
#    deploy, delete, reset, merge, a PR, Jira, Slack, "can't be undone") is
#    never blocked;
#  - otherwise Claude is told: do the step if it is inside what was asked,
#    local and reversible; keep the question, with its reason in one clause, if
#    not; drop it if the user is still drilling into details;
#  - stop_hook_active lets the second pass through whatever it says, so a
#    question Claude still judges necessary always reaches the user.
# Only the last paragraph is read, ignoring the held-back F-list under it.

JQ=$(command -v jq || echo /usr/bin/jq)
[ -x "$JQ" ] || exit 0
command -v perl >/dev/null 2>&1 || exit 0

input=$(cat)
[ "$(printf '%s' "$input" | "$JQ" -r '.stop_hook_active // false')" = true ] && exit 0

msg=$(printf '%s' "$input" | "$JQ" -r '.last_assistant_message // empty')
if [ -z "$msg" ]; then
  t=$(printf '%s' "$input" | "$JQ" -r '.transcript_path // empty')
  [ -f "$t" ] || exit 0
  msg=$(tail -n 400 "$t" | "$JQ" -rs '
    (map(.type == "user" and (.message.content | type) == "string") | rindex(true)) as $u
    | .[(($u // -1) + 1):]
    | map(select(.type == "assistant") | .message.content[]? | select(.type == "text") | .text)
    | join("\n")' 2>/dev/null)
fi
[ -n "$msg" ] || exit 0

verdict=$(printf '%s' "$msg" | perl -0777 -ne '
  s/\s+$//;
  my @lines = split /\n/;
  pop @lines while @lines && ($lines[-1] =~ /^\s*$/ || $lines[-1] =~ /^\s*\x{23B8}|^\s*\xE2\x8E\xB8/);
  my $last = "";
  for (my $i = $#lines; $i >= 0; $i--) { last if $lines[$i] =~ /^\s*$/; $last = "$lines[$i]\n$last" }
  exit unless $last =~ /\?\s*$/;
  exit unless $last =~ /\b(?:shall|should) I\b|\bdo you want (?:me|us) to\b|\bwould you like me to\b|\bwant me to\b|\bis (?:that|this) what you want\b|\b(?:ok|okay) to (?:go ahead|proceed|carry on)\b|\b(?:go ahead|proceed|carry on)\?/i;
  exit if $last =~ /\b(?:push|post|publish|deploy|delete|remove|drop|reset|force|merge|send|release|tag|irreversible|can.?t be undone|cannot be undone|outward|jira|slack|pull request|PR)\b/i;
  print "ask";
')
[ "$verdict" = ask ] || exit 0

cat >&2 <<'EOF'
This reply ends by asking permission for a next step. Decide which case it is
before ending the turn:

- The step is part of what the user already asked for, stays on this machine,
  and can be undone (an edit, a test run, a build, a read, a local commit the
  task implies): do it now, then report the result instead of asking.
- The step is outside what was asked, is a real choice between options, or
  changes something the user would have to undo: keep the question, and say in
  one clause why it needs them.
- The user is still asking about details rather than giving an instruction:
  drop the question; they will say when they are ready.

Doing the step that was asked for is not licence for the one after it. When in
doubt, keep the question — a needless question costs one message, an unwanted
change costs a revert.
EOF
exit 2
