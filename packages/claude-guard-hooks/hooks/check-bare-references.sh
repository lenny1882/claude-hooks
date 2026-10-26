#!/bin/bash
# Stop hook — refuses to end a turn whose reply uses a reference id without
# saying what it is: an F-number from a held-back list (F6), an answer code
# (1b, 2a), a GSD decision id (D-18) or a requirement id (ASGN-06, CHAT-01).
#
# Background. Between 28 Sep and 26 Oct 2026 the user had to ask what a bare
# reference meant, or ask for a question "again, fully", in eight sessions
# across four projects. Three memories covered it — keep-the-question-short and
# decision-ids-are-not-explanations in hugoboss-runner-api, and
# full-context-before-decisions in maestro-remote-mac — and none reached the
# other projects. Whether an id is explained in the reply is a mechanical
# question, so a hook can answer it every time.
#
# What counts as explained. The id is followed by its description — "F17.",
# "F17:", "F17 —", "F17 (…", "D-18 is the …", or a list line that starts with it —
# or it sits in parentheses after one: "the generated-files hook (F17)". Once
# explained anywhere in the reply, it may be used bare elsewhere in it. Code
# blocks and inline code are ignored.
#
# Jira keys (HBS-53, HBD20-1801) are not checked: the user works in them all
# day. Requirement ids are told apart by the leading zero GSD gives them.
#
# Honours stop_hook_active, so a false match costs one extra pass, not a loop.
# Needs perl; without it, or without jq, it lets the turn end.

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

bare=$(printf '%s' "$msg" | perl -0777 -ne '
  s/```.*?```//gs; s/`[^`\n]*`//g;
  my $id = qr/(?<![\w.\/-])(?:F\d{1,4}|D-\d{1,3}|[A-Z]{2,8}-0\d)(?![\w-])/;
  my $ans = qr/(?<![\w.\/-])[1-9][a-e](?![\w-])/;
  my (%seen, %ok);
  while (/($id)/g) { $seen{$1} = 1 }
  # An answer code ("1b") only counts as one when the sentence is about answers
  # or holds two of them; otherwise "3d" or "4b" is just a word.
  for my $s (split /(?<=[.!?])\s+|\n/) {
    my @a = $s =~ /($ans)/g;
    next unless @a;
    next unless @a > 1 || $s =~ /\b(?:option|answer|answers|choice|chose|chosen|picked|pick|recorded|noted|go with|went with|question)\b/i;
    $seen{$_} = 1 for @a;
  }
  for my $r (keys %seen) {
    my $q = quotemeta $r;
    $ok{$r} = 1 if
         /^[^\w\n]*(?:\*\*)?$q(?:\*\*)?[.:)]/m                    # list line: "F17." "**1b.**" "⎸ F17."
      || /$q(?:\*\*)?\s*(?:[:(]|—|–|\s-\s|\s(?:is|was) (?:the|a|an)\s|\smeans\s)/  # "F17: …" "D-18 is the …"
      || /\w+\W+\w+\W+\w+[^.\n]*\($q\)/;                          # "the generated-files hook (F17)"
  }
  print join(" ", sort grep { !$ok{$_} } keys %seen);
')
[ -n "$bare" ] || exit 0

cat >&2 <<EOF
This reply uses references without saying what they are: $bare

The user cannot hold every id from earlier in the session in their head, and
an answer like "1b" or "F6 is done" makes them scroll back or ask. Where each
one is used, say what it is in plain words — "F12 (adding the nine memory
files to their indexes)", "D-18, the rule that a deleted location sends the
user back to user select". Then end the turn.
EOF
exit 2
