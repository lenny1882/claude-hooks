# claude-guard-hooks — backlog

- **1.** A Stop hook for replies that end by asking permission for a step — parked until the "Finish the task" section of `~/.claude/CLAUDE.md` has had a week to work.

Next item number: 2.

---

## 1. A Stop hook for replies that end by asking permission for a step — **PARKED**

**What.** A `Stop` hook, `check-question-ending.sh`, that reads the last
paragraph of the reply, ignoring the held-back F-list under it, and acts only
when that paragraph asks permission for a next step: "Shall I…?", "Should I…?",
"Do you want me to…?", "Would you like me to…?", "Want me to…?", "Is that what
you want?", "OK to go ahead?".

- **Never sent back:** a question that names an outward-facing or hard-to-undo
  step — push, post, publish, deploy, delete, remove, drop, reset, force, merge,
  send, release, tag, PR, pull request, Jira, Slack, "can't be undone".
- **Sent back once** with three cases to choose between:
  - the step is inside what was asked, local and reversible: do it, then report;
  - it is outside the request, a real choice, or something the user would have
    to undo: keep the question and give its reason in one clause;
  - the user is still asking about details: drop the question.
  The message ends: doing the step that was asked for is not licence for the
  next one, and when in doubt, keep the question.
- **`stop_hook_active`** lets the second pass through whatever it says, so a
  question Claude still judges necessary always reaches the user.

A working version with 13 tests was built and taken out again before release
(commits `33eaca7` and `614ad1b` on `main`); `git show 33eaca7` has the script
and its tests.

**Why.** Stopping to ask about steps inside a task the user has already given
is the most frequent repeat correction in the September–October sessions. The
memory meant to prevent it was never in its project's index, so it never
loaded. The hook has to avoid the opposite failure: changes made because a hook
said "stop asking", which the user then has to revert. That is why it is a
nudge with a default of keeping the question, not a rule.

**To do.**
1. After a week of sessions with the new "Finish the task" section of
   `~/.claude/CLAUDE.md`, scan the transcripts for corrections about stopping to
   ask or drip-feeding.
2. If they have stopped, close this item. If not, decide with the user from the
   cases that remain: whether to build the hook as designed, narrow its
   trigger (for example, only when the user's last message was an instruction
   rather than a question), or only log matches for review instead of sending
   the reply back.
