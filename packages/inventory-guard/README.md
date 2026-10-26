# inventory-guard

A `Stop` hook that will not let a turn end while something is installed into
your Claude config that `INVENTORY.md` does not mention.

The problem it solves is drift. Small hooks and skills get built, installed, and
then forgotten — they work, so nobody looks at them again, and a year later the
only copy is the installed one with no source, no tests and no note of why it
exists. This makes the record maintain itself: install something, and the next
turn ends with Claude being told to write it down.

Part of [claude-hooks](https://github.com/lenny1882/claude-hooks), which holds several packages
that are each versioned, released and installed on their own.

## What it watches

By name, against the contents of the inventory file:

- `~/.claude/hooks/*.sh` — backups matching `*.bak*` are ignored
- `~/.claude/skills/*/`
- `~/.claude/bin/*` and `~/.local/bin/claude-*` — the `claude` binary itself is skipped

Matching is a plain substring search for each basename, so the inventory can be
laid out however you like as long as it names things.

## Install

Needs `curl`, `tar` and `jq`. From the newest release:

    v=$(curl -fsSL https://raw.githubusercontent.com/lenny1882/claude-hooks/versions/versions.txt | awk '$1=="inventory-guard" {print $2}')
    curl -fsSL "https://github.com/lenny1882/claude-hooks/releases/download/inventory-guard-v$v/inventory-guard.tar.gz" | tar -xz
    cd inventory-guard && ./install.sh

These lines never change between versions: `versions.txt` names the newest
stable release, and only once its tarball is uploaded. To pin a version,
download `.../releases/download/inventory-guard-vX.Y.Z/inventory-guard.tar.gz` instead.

Or from a clone of the whole repo:

    git clone https://github.com/lenny1882/claude-hooks && cd claude-hooks/packages/inventory-guard
    ./install.sh              # install
    ./install.sh --link       # or symlink, so edits in the checkout are live
    ./install.sh --dry-run    # show the settings change, write nothing
    ./install.sh --yes        # no prompts

Re-running the installer is safe and is how you upgrade. It merges into
`settings.json` rather than replacing it, backs the file up first, and only ever
touches its own entries. If Claude Code is already running, `/hooks` forces a
settings reload.

Needs `jq`. Merges into `settings.json`, touching only its own `Stop` entry —
`claude-notify`'s stop sound is left alone, and there is a test for that.

    CLAUDE_INVENTORY=/some/other/INVENTORY.md ./install.sh

sets a different target; the default is `~/claude-sandbox/INVENTORY.md`.

A newly registered hook needs a Claude Code restart; `/hooks` only reloads
changes to existing ones.

## Not nagging

Three things stop it becoming noise:

- **`stop_hook_active`** is honoured. The harness sets it once a Stop hook has
  already blocked, and warns that hooks must return success while it is true —
  otherwise a hook that can't be satisfied loops until a cap is hit.
- **Once per session.** After it speaks it writes a marker under
  `~/.claude/inventory-guard/` and stays quiet for the rest of that session, even
  if you ignore it. Markers older than a week are cleaned up on the next run.
- **`touch ~/.claude/.no-inventory-check`** turns it off entirely.

It also exits quietly if `jq` is missing or the inventory file does not exist —
no point blocking a turn when there is nowhere to write the answer.

## Update

    ./update.sh            check, ask, upgrade, reinstall
    ./update.sh --check    report what is available and stop

Reads this package's line in `versions.txt`, so pre-releases, and releases of
the other packages in the repo, are never offered. Works from a downloaded
tarball as well as a clone — no git needed.

## Uninstall

    ./uninstall.sh                 ask before editing settings.json
    ./uninstall.sh --keep-settings leave settings.json alone

## Tests

    ./test/run-tests.sh

Redirects `HOME` and `CLAUDE_DIR` into a temp directory, so your real config is
never touched. `./test/run-tests.sh` at the repo root runs every package's.

Covers the block, the once-per-session limit, all three watched locations, both
guards, the opt-out, and that installing and uninstalling leave other `Stop`
hooks intact.

## The inventory file, and what this package does not do

The hook only reads `INVENTORY.md`. It never writes to it, has no way to create
one, and nothing in the package regenerates it. When it finds something missing
it prints the names to stderr and exits 2, and the rows are then written by
Claude in response to that message. That is the only path by which the file ever
changes.

Keeping the contents hand-written is deliberate. The rows carry judgement — what
a thing is, where its source lives, whether it still needs packaging — and none
of that can be generated. A stub row appended automatically would satisfy the
substring match and silence the guard while recording nothing, turning the
record into a list of names.

### What a fresh install actually gets you

On a machine with no `INVENTORY.md`, installing this gives you a hook that exits
at the file-exists check, blocks nothing and says nothing, indefinitely. There
is no way to tell that apart from a working install. Three things it needs sit
outside the package:

1. **The file.** `install.sh` does not create one.
2. **The format** — the status meanings (shipped, packaged, loose) and the table
   shape. These exist only as prose inside the `INVENTORY.md` on this machine,
   which the package does not ship.
3. **The rules the hook cannot enforce.** Its stderr message carries the
   instruction to add a row and keep the format, so that much travels with the
   package. But a row is also wanted when a new source directory is created, and
   when something's packaging status changes. The hook only ever sees installed
   files, so it cannot prompt for either.

The first two are fixable here: ship a starter `INVENTORY.md` with the format in
it, and have `install.sh` place it when none is found. The third is not. The
hook has no way to detect those cases, so the package should say plainly that it
needs a per-machine instruction rather than assume one has been written. On this
machine that instruction is in `claude-sandbox/CLAUDE.md`.

### Where the file lives, and who owns what

The file stays outside this package, in `claude-sandbox`. It records everything
built for the machine rather than anything about this hook, and holding it
inside one package would make it read as that package's own data. What the
package should own is that the file exists and what shape it takes, not what
goes in it.

With the guard uninstalled, the document's currency depends entirely on that
`claude-sandbox/CLAUDE.md` instruction, and nothing checks whether it was
followed. That is not hypothetical: while this hook was uninstalled,
`INVENTORY.md` went stale in exactly the way it exists to prevent. It listed
`inventory-check.sh` and `claude-package-kit` under "Installed as" when neither
was on disk, and said at the top that a hook was keeping it honest. On its own
the file is a record that depends on someone remembering, which is the argument
for shipping the two together.

## Status

As of 18 Aug 2026, not installed anywhere, and nothing from it is on disk. It is
waiting on being uploaded to GitHub and packaged as something installable, so
that install will be a clean start rather than an upgrade over a hand-placed
copy.

## Releasing

`/release inventory-guard` at the repo root — bump `packages/inventory-guard/VERSION` on `main`,
move `release/inventory-guard-vX.x` onto it, tag `inventory-guard-vX.Y.Z` there. The tag is what
publishes it. The release carries what `PAYLOAD` lists, and nothing else in
this directory.
