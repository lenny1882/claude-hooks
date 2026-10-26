#!/bin/bash
# PostToolUse and PostToolUseFailure hook (matcher: Bash) — when Bash's sandbox
# refuses a write, tells Claude at that moment that the path is writable with
# the Write and Edit tools, and how to word a hand-off when one is unavoidable.
#
# Background. The sandbox gates Bash only. A `cp`, `tee` or `git remote add`
# that fails with "Read-only file system" or "could not lock config file" says
# nothing about the file; Write and Edit reach it. ~/.claude/reference/
# this-machine.md has said so for months, and on 26 Oct 2026 Claude still told
# the user four times in two hours that ~/claude-sandbox or .git/config "can't
# be written" and handed over a `! cp`. The reference is read at session start;
# by the time a write fails mid-task it no longer steers anything. This hook
# puts the rule next to the error, which is where the decision is made.
#
# Why both events. A command that exits non-zero arrives as PostToolUseFailure;
# one where the failed write sits mid-pipeline or before a `;` exits 0 and
# arrives as PostToolUse. Half of that day's blocked writes were the second
# kind. Exit 2 puts stderr in front of the model on both.
#
# Why the patterns are shaped like errors rather than bare phrases. Claude
# reads this-machine.md, which quotes "Read-only file system" in prose; a bare
# match would fire every time the reference is read. The patterns need the
# punctuation an error message has: "path: Read-only file system", "[Errno 30]".
# "Permission denied (publickey)" and git's ".gitmodules: Permission denied"
# warning are not write blocks and are not matched.

JQ=$(command -v jq || echo /usr/bin/jq)
[ -x "$JQ" ] || exit 0   # no jq: fail open rather than break every Bash call

input=$(cat)

# PostToolUse carries tool_response; PostToolUseFailure carries error.
text=$(printf '%s' "$input" | "$JQ" -r '
  [ (.tool_response | if type == "object" then (.stdout // ""), (.stderr // "")
                      elif type == "string" then . else empty end),
    (.error // empty | tostring) ] | join("\n")' 2>/dev/null) || exit 0

hit=$(printf '%s' "$text" | grep -m1 -E \
  "(: |\] )Read-only file system|\bEROFS\b|could not lock config file|Unable to create '[^']*\.lock'" \
  | cut -c1-200)
[ -n "$hit" ] || exit 0

cat >&2 <<EOF
Bash's sandbox blocked a write:

  $hit

The sandbox gates Bash only. The path is not read-only and the disk is not
read-only. Do not tell the user it cannot be written, and do not hand them a
\`!\` command for a change to a file's contents.

- Changing a file (create, edit, append, .git/config, a memory, a file under
  ~/claude-sandbox or ~/.claude): Read it, then Write or Edit the same path.
  Carry on with the task.
- A maestro-drive script that has to write (a build, adb): start the bridge
  with the mcp__maestro-bridge__bridge tool and run it with TRANSPORT=bridge.
- Anything else that only Bash can do (rm, mv, git commit, a build outside
  maestro-drive, a package install): give the user one \`!\` line, introduced
  as "Bash's sandbox blocks writes to <path>", never as "can't write" or
  "read-only".

See ~/.claude/reference/this-machine.md.
EOF
exit 2
