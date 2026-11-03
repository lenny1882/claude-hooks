# claude-guard-hooks — backlog

- **1.** A Stop hook for replies that end by asking permission for a step — parked until the "Finish the task" section of `~/.claude/CLAUDE.md` has had a week to work.
- **2.** A UserPromptSubmit hook that makes Claude read each message against the work in progress before replying — open.

Next item number: 3.

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

## 2. A UserPromptSubmit hook that makes Claude read each message against the work in progress — **OPEN, raised 2 Nov 2026**

**What.** A `UserPromptSubmit` hook, `check-read-in-context.sh`, that adds a
short instruction to Claude's context alongside every message the user types.
Slash commands are skipped. The instruction says, before replying:

- name the work in progress: the item, step or mode the conversation is in
  (for example, going through decisions one at a time);
- read the message as a change to that work, not as a new task: work out which
  item it applies to, and whether it changes the current step, the items still
  to come, or the whole task;
- keep the current mode (one at a time, a draft under review, a single file)
  unless the message says to leave it;
- if two readings lead to different replies and the thread doesn't settle
  which, ask which, in one line, instead of picking one.

The hook only adds context. It never blocks the message.

**Why.** In a claude-skills session on 2 Nov 2026, the user was going through
decisions one at a time and asked for the reason to be given with each
decision. Claude read it as a new request and gave the whole list of decisions
at once, with reasons. The intended reading was to keep going one at a time and
add the reason to each one. Each misreading like this costs a correction and
a second reply. Writing rules in `~/.claude/CLAUDE.md` don't help, because
Claude doesn't think it has misread anything, so no rule triggers.

**Open questions.**
1. Trigger on every message, or only on short ones (under about 30 words)?
   Short follow-ups that rely on the thread for meaning are where this goes
   wrong. Every message is simpler and costs about 100 tokens of context
   per turn.
2. Add a second check after the reply? A `Stop` hook with `type: "prompt"`
   would have a small model judge whether the reply's shape matches the
   message in context. One example of a mismatch is a full list when the
   thread was going one at a time. First check what input a prompt-type
   `Stop` hook receives. If it doesn't get the user's last message and the
   reply, it can't make this judgement.
3. Measure first. Scan September–November transcripts for corrections of
   the form "no, I meant…" or "I asked for X, not Y", and use them as test
   cases for the instruction text.
