# handoff-gate

A Claude Code hook that stops `/compact` until there is an up-to-date handoff,
and asks the session to write one.

Compaction replaces a conversation with a summary. What the summary keeps is not
under your control, and the things that matter most — the decision you rejected
an hour ago, the assumption you corrected, the half-finished edit — are exactly
what a summariser drops. This makes the model write a handoff file first, while
it still has the whole conversation in front of it.

Part of [claude-hooks](https://github.com/lenny1882/claude-hooks), which holds several packages
that are each versioned, released and installed on their own.

## What you actually see

Press `/compact`. It is cancelled, with a line telling you why. The session then
starts writing the handoff on its own. When it says it is done, press `/compact`
again and it goes through — and the summary is additionally told to stay
consistent with what was just written.

So the first `/compact` of any session is always cancelled. That is deliberate:
by the time you reach for it you have done a session's worth of work, so the
handoff is by definition out of date.

## Install

Needs `curl`, `tar` and `jq`. From the newest release:

    v=$(curl -fsSL https://raw.githubusercontent.com/lenny1882/claude-hooks/versions/versions.txt | awk '$1=="handoff-gate" {print $2}')
    curl -fsSL "https://github.com/lenny1882/claude-hooks/releases/download/handoff-gate-v$v/handoff-gate.tar.gz" | tar -xz
    cd handoff-gate && ./install.sh

These lines never change between versions: `versions.txt` names the newest
stable release, and only once its tarball is uploaded. To pin a version,
download `.../releases/download/handoff-gate-vX.Y.Z/handoff-gate.tar.gz` instead.

Or from a clone of the whole repo:

    git clone https://github.com/lenny1882/claude-hooks && cd claude-hooks/packages/handoff-gate
    ./install.sh              # install
    ./install.sh --link       # or symlink, so edits in the checkout are live
    ./install.sh --dry-run    # show the settings change, write nothing
    ./install.sh --yes        # no prompts

Re-running the installer is safe and is how you upgrade. It merges into
`settings.json` rather than replacing it, backs the file up first, and only ever
touches its own entries. If Claude Code is already running, `/hooks` forces a
settings reload.

Needs Claude Code 2.1.228 or later. Hooks are read at startup, so restart
Claude Code before testing.

## Where the handoff goes

- A project with a `.planning/` directory: `.continue-here.md`, via GSD's own
  `/gsd:pause-work`, so there is one handoff rather than two.
- Anywhere else: `HANDOFF.md` at the git root, or the working directory if it is
  not a repo.

## Getting past it

- `/compact skip handoff` — once, straight through.
- `touch .nohandoff` in a project — that directory never asks again.

## Update

    ./update.sh            check, ask, upgrade, reinstall
    ./update.sh --check    report what is available and stop

Reads this package's line in `versions.txt`, so pre-releases, and releases of
the other packages in the repo, are never offered. Works from a downloaded
tarball as well as a clone — no git needed.

## Uninstall

    ./uninstall.sh                 ask before editing settings.json
    ./uninstall.sh --keep-settings leave settings.json alone

## How it works

Three undocumented properties of the `PreCompact` hook, read out of the compiled
binary at 2.1.228 and confirmed by running them:

- **Exit 2 cancels the compaction.** Your stderr is shown to the user as
  `Compaction blocked by PreCompact hook: …`. The model never sees it.
- **stdout on exit 0 becomes the compaction instructions.** That is how the
  passing case steers what the summary keeps.
- **`asyncRewake: true` wakes the session.** The hook is backgrounded, and on
  exit 2 its stderr is injected as a system-reminder that starts a turn. This is
  the only way a hook can hand work to the running model. It lives in the shared
  hook runner rather than the Stop-specific path, which is why it works here.
  `rewakeMessage` and `rewakeSummary` are marked `@internal` in the schema, so an
  update could withdraw them — see *If it stops working*.

Both roles are the same script, switched by its first argument. `gate` runs
synchronously and decides; `wake` runs in the background, waits for the gate's
verdict, and pushes the job into the session.

Freshness is deliberately dumb: a marker file is written when the gate cancels,
and the handoff counts as current if it was modified after that marker. No clock
heuristics, nothing to tune. State lives in `~/.claude/handoff-gate/` and can be
deleted at any time; the worst outcome is one extra prompt.

## Why it is built this way

**It blocks rather than writing the handoff itself.** A separate headless Claude
reading the transcript was the obvious alternative, and was rejected for two
reasons. Transcripts are five to thirty times larger than a context window, so
it sees a sliver of the session. And it would overwrite a considered handoff
with a chronology nobody reviewed. The live session has the working state, and
you see what it writes.

**Freshness is a marker file, not a clock.** The cost is that a `/compact` right
after writing a handoff of your own accord is still cancelled once, because the
gate has not yet written a marker for it to be newer than. One keypress, in
exchange for nothing to tune.

**It fires in every project, not only ones that already have a `HANDOFF.md`.**
That includes scratch directories, which makes it the behaviour most likely to
annoy. `.nohandoff` is the answer for one directory. If it grates everywhere,
the cheap change is for the gate to exit 0 when no handoff file exists yet.

## If it stops working

If `/compact` is cancelled and then nothing happens, `asyncRewake` is no longer
firing. Set `FALLBACK=1` at the top of the hook and a separate headless Claude
writes the handoff instead, from the transcript.

That path is off because it is worse, not because it is unfinished. Transcripts
run to megabytes — 5.5 MB is ordinary and one here was 26 MB, against a context
window of roughly 800 KB — so the fallback trims to the last stretch of real
conversation with tool output stripped, and still only sees a chronology rather
than the working state. It appends a dated section instead of overwriting, so a
good handoff is never replaced by a worse one.

Also worth knowing: a hook that times out counts as *failed*, not blocked, so
the compaction proceeds with no handoff and only a one-line notice. The default
timeout is 600 seconds and the gate does nothing slow, so this should not arise
— but if handoffs ever start silently not happening, look here first.

## Tests

    ./test/run-tests.sh

Redirects `HOME` and `CLAUDE_DIR` into a temp directory, so your real config is
never touched. `./test/run-tests.sh` at the repo root runs every package's.

Covers the gate cycle, both escape hatches, target selection, and that
installing twice does not duplicate the entry.

Run only on Linux so far, with bash 5 and jq 1.6. The BSD/GNU `stat` split is
handled and nothing else is GNU-only, so it should work on macOS — but that is
reasoning, not a test.

## Releasing

`/release handoff-gate` at the repo root — bump `packages/handoff-gate/VERSION` on `main`,
move `release/handoff-gate-vX.x` onto it, tag `handoff-gate-vX.Y.Z` there. The tag is what
publishes it. The release carries what `PAYLOAD` lists, and nothing else in
this directory.
