#!/bin/bash
# Stop hook — flags a reply that tells the user a file cannot be written, or
# hands them a `!` command that only writes a file. The user sees one line;
# with their next prompt, Claude is told to do the write with the Write or
# Edit tool (deliver-stop-guidance.sh).
#
# Background. redirect-blocked-write.sh speaks when a Bash write fails. This is
# the second layer, for when that advice is ignored: it reads the reply itself.
# Every one of the four corrections on 26 Oct 2026 was of a reply in exactly
# this shape: "~/claude-sandbox is read-only from this session. To put it in
# place, type: ! cp …". Writing the file costs one tool call; being told to do
# it by hand cost the user a message each time.
#
# What it looks for. Either of:
#  - a first-person claim that something cannot be written ("I can't write",
#    "is read-only from this session", "the sandbox won't let me write");
#  - a `!` line whose command only puts content in a file: cp, tee, touch,
#    echo/printf/cat redirected into a file, git remote add/set-url, git config.
#    A redirect on any other command is taken as capturing its log — `rm -v …
#    > /tmp/x.log` deletes files, which Write and Edit cannot do.
# The command names count only as commands — a space or separator before, a
# space after — so `./install.sh` or `scripts/cp-assets.sh` is not a write.
# A `! git push` or `! rm` hand-off is not matched; those have no Write or Edit
# equivalent and are allowed, provided they are not introduced as "can't write".
# The phrases are first-person on purpose: a reply that quotes an error or
# discusses this hook should not be sent back.
#
# Ignores a turn that another Stop hook has already sent back
# (stop_hook_active).

JQ=$(command -v jq || echo /usr/bin/jq)
[ -x "$JQ" ] || exit 0

input=$(cat)
[ "$(printf '%s' "$input" | "$JQ" -r '.stop_hook_active // false')" = true ] && exit 0

msg=$(printf '%s' "$input" | "$JQ" -r '.last_assistant_message // empty')

# Older Claude Code sends no last_assistant_message. Fall back to the text
# blocks of the assistant entries after the last prompt the user typed. Only
# the tail is read; transcripts run to tens of megabytes.
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

claim=$(printf '%s' "$msg" | grep -m1 -i -o -E \
  "\b(I|we) (can'?t|cannot|could ?n.?t|am unable to|was unable to) (write|save|create|update|edit|touch|overwrite)[^.]{0,60}|\b(is|are) read-only (from|in|for|inside) (this|the) (session|sandbox|shell)|sandbox (can'?t|cannot|won'?t let me|doesn'?t let me) (write|save)[^.]{0,60}")

handoff=$(printf '%s' "$msg" | grep -m1 -o -E \
  "^[[:space:]]*!.*(^|[[:space:];&|(])(cp|tee|touch|install)[[:space:]][^|]*$|^[[:space:]]*!.*\b(echo|printf|cat)\b[^|;&]*[^2&]>>? *[~/.\$\"'][^ ]*|^[[:space:]]*!.*\bgit( -C [^ ]+)? (remote (add|set-url)|config)\b.*" \
  | cut -c1-160)

[ -n "$claim$handoff" ] || exit 0

guidance=$({
  echo "Your previous reply handed the user a write that the Write or Edit tool can do:"
  echo
  [ -n "$claim" ]   && echo "  $claim"
  [ -n "$handoff" ] && echo "  $handoff"
  echo
  cat <<'EOF'
The sandbox gates Bash only; Write and Edit reach ~/claude-sandbox, ~/.claude,
.git/config and everywhere else Bash's writes fail. Unless the user's new
message has made it moot, do the write now: Read the file, then Write or Edit
it, and tell the user in one line that it is written, with no "can't write" or
"read-only" claim.

If what you handed over really has no Write or Edit equivalent (rm, mv of a
directory, git commit, a build), keep it as one `!` line, introduced as "Bash's
sandbox blocks writes to <path>", and say nothing about the path being
unwritable. See ~/.claude/reference/this-machine.md.
EOF
})

# The user sees one line. Claude gets the guidance with the user's next prompt,
# through deliver-stop-guidance.sh: anything a Stop hook sends Claude directly
# is printed to the user in full.
sid=$(printf '%s' "$input" | "$JQ" -r '.session_id // empty' | tr -cd 'A-Za-z0-9_-')
if [ -n "$sid" ]; then
  dir="${CLAUDE_DIR:-$HOME/.claude}/claude-guard-hooks/pending"
  mkdir -p "$dir" && printf '%s\n' "$guidance" > "$dir/$sid.check-write-handoff.txt"
fi
"$JQ" -n '{ systemMessage: "Reply handed you a write Claude can do itself" }'
exit 0
