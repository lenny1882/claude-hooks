# claude-guard-hooks — backlog

- **1.** A Stop hook for replies that end by asking permission for a step — parked until the "Finish the task" section of `~/.claude/CLAUDE.md` has had a week to work.
- **2.** A Stop hook for a `!` command handed over without where it runs or how to get the key it needs.
- **3.** A Stop hook that checks a reply against the project's parked and dropped items.
- **4.** A PreToolUse hook that refuses `git commit --amend`, reverts, removals and planning-doc edits nobody asked for.
- **5.** A Stop hook for a logging command handed over without a monitor armed.
- **6.** A Stop hook that makes a "what's left" list name what was swept.
- **7.** A PreToolUse hook that refuses a script for the user that does not log to a file Claude can read.

Next item number: 8.

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

**More evidence (9 Nov 2026, from claude-skills).** A review of 2,140 typed
user messages, 12 Oct to 9 Nov 2026, found about five more complaints of
stopping to ask when the step could be done: "Then do it.", "Why are you
stopping to ask?". Counts are from keyword hits only. This was candidate 6 of
item 6 in claude-skills' BACKLOG.md ("Recurring faults to consider for
hooks"). The window overlaps the week the To do step waits for, so the scan in
step 1 should start from these.

---

The six items below came from claude-skills on 9 Nov 2026: item 6 of its
BACKLOG.md, "Recurring faults to consider for hooks". Its source was a review
of 2,140 typed user messages across all projects, 12 Oct to 9 Nov 2026; the
counts are rough, from keyword hits only. Each fault already has a rule in
`~/.claude/CLAUDE.md` except where noted; the complaints show the rule is not
always followed, often with "how many times" in the complaint. Two more
candidates from the same list went elsewhere: stopping to ask is merged into
item 1, and giving up on a sandbox write error is already handled by
`redirect-blocked-write.sh` and `check-write-handoff.sh`.

## 2. A Stop hook for a `!` command handed over without where it runs or its key

**What.** A `Stop` hook that finds a command handed to the user (a `!` line, or
a fenced command introduced as one for the user to run) and checks the reply
says where it runs (`!` in Claude Code or the user's own terminal) and, when
the command needs a short-lived key or login (AWS SSO, a token, `aws sso
login`), how to get it. Wakes Claude to add what is missing.

**Why.** About 10 complaints of steps skipped or fixes handed out one at a
time; the example was a command given without how to get the key it needs.
CLAUDE.md rules: "Finish the task", "Say where every command runs". The
claude-skills `/owl` skill (`packages/owl`, 0.1.0, not yet released) repairs
this after the reply has gone out; this would catch it before.

**To do.** Decide how a key-needing command is recognised (a list of CLIs that
take a profile or token is the likely start). Drip-feeding one fix per message
is not mechanical to detect and stays with item 1 and `/owl`.

## 3. A Stop hook that checks replies against parked and dropped items

**What.** A per-project list of items the user has parked ("this will wait")
or dropped, and a `Stop` hook that wakes Claude when a reply offers or flags
one of them again.

**Why.** About 6 complaints: a dropped option offered again; an item marked
"this will wait" flagged again. No CLAUDE.md rule covers it.

**To do.** Decide where the list lives and who writes it — a hook cannot tell
from a reply that an item was parked, so something has to record it when the
user says so (a UserPromptSubmit hook matching "this will wait", "drop it", or
a skill). Matching a reply against free-text items needs a looser test than
the other hooks use; decide whether a false match costs more than the miss.

## 4. A PreToolUse hook on unasked destructive or state-changing actions

**What.** A `PreToolUse` hook on Bash and Edit/Write that denies `git commit
--amend`, `git revert`, `git reset`, `rm` of tracked files, and edits to
planning docs (`.planning/`, ROADMAP.md, STATE.md, BACKLOG.md), and tells
Claude to ask the user first unless the user's last message asked for exactly
that. It denies rather than asks, for the reason under "Why they deny rather
than ask" in the README.

**Why.** About 6 complaints: removing, amending, reverting, or starting a
session hours after the request. "Did I ask you to remove it from the planning
docs?", "Did I ask you to amend?". CLAUDE.md rule: "No starting work unless
asked".

**To do.** The hard part is letting the asked-for case through: decide whether
the hook reads the last user message from the transcript for the verb
("amend", "remove", "revert"), or whether a denial and one retry is
acceptable. `rm` of untracked scratch files must stay allowed.

## 5. A Stop hook for a logging command handed over without a monitor armed

**What.** A `Stop` hook that finds a command for the user whose output goes to
a log Claude can read (a path under `/tmp/` or the scratchpad, or a script
known to log) and wakes Claude when the same turn did not arm a Monitor.

**Why.** About 5 complaints; "tell me when it finishes" was said for a script
that logs where Claude can read it. CLAUDE.md rule: "Watching a run".

**To do.** Check the transcript's turn for a Monitor tool call; decide how a
logging command is recognised without the script's source to hand.

## 6. A Stop hook that makes a "what's left" list name what was swept

**What.** A `Stop` hook that, when the user's last message asks what is left
to test, check or do, wakes Claude if the reply does not name what was swept.

**Why.** About 3 complaints of lists that change each time they are asked for.
CLAUDE.md rule: "'What's left' lists come from a full sweep".

**To do.** A hook can check the reply names a sweep, not that the sweep
happened; decide whether also checking the turn for a repo-wide grep is worth
it.

## 7. A PreToolUse hook on a script for the user that does not log

**What.** A `PreToolUse` hook on Write that, for a new shell script the user
will run, denies it when it has no log path built in (an `exec > >(tee …)`, a
`LOG=` under `/tmp/`, or similar) and says to add one.

**Why.** About 3 complaints. CLAUDE.md rule: "Scripts log where Claude can read
them".

**To do.** Decide how "a script for the user" is told apart from scripts
Claude runs itself or a package's own hooks and tests — a path outside the
repo's `hooks/`, `test/` and `lib/` is the likely start.
