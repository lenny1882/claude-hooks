# claude-guard-hooks

Small hooks that stop Claude Code going wrong in a way you would otherwise
have to correct by hand: doing something quietly that should involve a
person, handing you work it can do itself, editing generated files, printing
credentials, and references you have to ask about. They are packaged together
because each one holds Claude to a rule it already has and does not follow
unprompted — usually one written down as a memory in a single project, which
never reached the others.

Part of [claude-hooks](https://github.com/lenny1882/claude-hooks), which holds several packages
that are each versioned, released and installed on their own.

## Why they deny rather than ask

Hooks can return `ask`, which sounds like the obvious fit — put it to the user.
In auto mode it does not reach the user at all: the harness resolves an `ask`
decision through the same classifier that approves ordinary tool calls, and it
approved a test command silently. `deny` is the only decision beyond its reach.

So both `PreToolUse` hooks deny, and spend their refusal text telling Claude what to ask you.
That is the whole design. If either is ever "simplified" to `ask`, it stops
working and nothing visibly breaks.

The one place this does not apply is `check-discuss-batch.sh`'s second event,
`UserPromptExpansion`, which never had an `ask` to reject — see below.

## gate-unsandboxed-bash.sh

Matcher `Bash`. Denies any call carrying `dangerouslyDisableSandbox`.

This is the second of two layers. The first is `sandbox.allowUnsandboxedCommands:
false` in `settings.json`, which makes the parameter inert harness-side and is
the actual enforcement. The hook exists so the refusal arrives as a clear
instruction — stop and ask the user — rather than as a puzzling sandbox failure
Claude then tries to route around. Claude's built-in guidance is to retry
unsandboxed as soon as a command looks like it failed for sandbox reasons, which
turns the sandbox from a boundary into a routing hint: wrong door, try the other.

To genuinely allow an unsandboxed command, remove `allowUnsandboxedCommands` and
disable this hook. Both, deliberately — the point is that it takes a person.

If `jq` is missing the hook exits 0 rather than failing every Bash call.

## check-discuss-batch.sh

Denies `/gsd:discuss-phase` and `/bm:discuss-phase` when they run without a flag
that settles how questions are asked. Without one, discuss-phase asks one
question per turn, which is slow and hard to follow.

Passes straight through on `--batch`, `--batch=N`, `--auto`, `--power`, and
`--no-batch`. That last one is not a GSD flag — GSD ignores it — and exists only
so you can deliberately choose the one-at-a-time flow.

The flag is `--batch`, not `--batched`. An earlier version of this fix lived as a
patch inside the GSD plugin and was wiped by an update, which is why it is a hook
in your own config now.

### It is registered on two events, because there are two ways in

**`PreToolUse`, matcher `Skill`** — Claude calls the skill. This denies the call
and tells Claude to put the choice to you with AskUserQuestion first.

**`UserPromptExpansion`, no matcher** — you type `/gsd:discuss-phase` yourself.
That never becomes a Skill tool call, so `PreToolUse` never fires for it, and for
a while this hook only caught Claude and not you.

The two paths need different messages, not just different plumbing. When a
`UserPromptExpansion` hook blocks, the harness sets `shouldQuery: false` and
Claude is never invoked, so there is nobody to carry out an instruction. The
message is printed to you as a terminal warning, followed by `Original prompt:
/gsd:discuss-phase 3`. So this branch says what to retype and nothing else.
Telling Claude to ask you would go nowhere: Claude is not running.

The event's matcher is compared against `command_name`, so a matcher could
narrow it. It is registered without one anyway: the exact name a plugin skill
registers under is not worth betting on, a matcher that misses fails silently
with no sign anything is wrong, and the script filtering costs one `jq` call per
slash command. It also accepts a bare `discuss-phase` and falls back to the first
word of `prompt` if `command_name` is ever absent.

## redirect-blocked-write.sh

`PostToolUse` and `PostToolUseFailure`, matcher `Bash`. When a Bash command's
output shows the sandbox refusing a write — `path: Read-only file system`,
`[Errno 30]`, `EROFS`, `could not lock config file`, `Unable to create
'….lock'` — it exits 2, and its stderr goes to Claude: the path is writable with
the Write and Edit tools, maestro-drive scripts go through the bridge, and
anything that only Bash can do is handed over as one `!` line introduced as
"Bash's sandbox blocks writes to <path>", never "can't write".

The sandbox gates Bash only, and `~/.claude/reference/this-machine.md` says so.
On 26 Oct 2026 Claude still told you four times in two hours that
`~/claude-sandbox` or `.git/config` could not be written, and handed over a
`! cp` each time. A rule read at session start has stopped steering anything by
the time a write fails mid-task; this puts it next to the error.

It is on both events because a write that fails inside a pipeline, or before a
`;`, exits 0 and only reaches `PostToolUse`, while a command that exits
non-zero only reaches `PostToolUseFailure`. The patterns need the punctuation
an error has, so reading `this-machine.md`, which quotes the same phrase in
prose, does not set it off. `Permission denied (publickey)` and git's
`.gitmodules` warning are not write blocks and are ignored.

## check-write-handoff.sh

`Stop`, no matcher. The second layer, for when the first is ignored: it reads
the reply and refuses to end the turn if it claims, in the first person, that
something cannot be written ("I couldn't save it", "is read-only from this
session", "the sandbox won't let me write"), or hands you a `!` command that
only writes a file — `cp`, `tee`, `touch`, a `>` redirect, `git remote add`,
`git config`. Claude is sent back to do the write with Write or Edit and
rewrite the reply.

`! git push`, `! rm` and a build are allowed; they have no Write or Edit
equivalent. It reads `last_assistant_message`, and falls back to the
transcript's tail on a Claude Code too old to send it. It honours
`stop_hook_active`, so a false match costs one extra pass, not a loop.

## guard-generated-files.sh

`PreToolUse`, matcher `Edit|Write|MultiEdit|NotebookEdit|Bash`. Denies a hand
edit to a generated file and says to change the generator's source and run
the generator instead — or, if it genuinely cannot run, to stop and say what
blocks it.

A file counts as generated by its name (`*.g.dart`, `*.gr.dart`,
`*.freezed.dart`, `*.mocks.dart`, `*.pb.dart`, `*.pb.go`, `*_pb2.py`, and the
lock files: `pubspec.lock`, `Podfile.lock`, `package-lock.json`, `yarn.lock`,
`pnpm-lock.yaml`, `go.sum`, `Cargo.lock`, `poetry.lock`, `composer.lock`,
`Gemfile.lock`) or by a header in its first five lines — "GENERATED CODE",
"DO NOT EDIT", "DO NOT MODIFY", "@generated", "auto-generated". Content being
written that carries such a header is refused too.

On Bash it refuses only the hand-edit forms — `sed -i`, `perl -i`, a redirect
or `tee` into a generated name. Running the generator writes the same files and
is exactly what should happen.

The rule was a memory in two projects and a section of `~/.claude/CLAUDE.md`,
and a plan still hand-edited `routes.gr.dart` on 21 Oct 2026.

## guard-secret-files.sh

`PreToolUse`, matcher `Read|Bash`. Denies printing `.env` and its variants,
`.netrc`, `~/.aws/credentials`, SSH private keys and Bruno environment files.
Templates (`.env.example`, `.sample`, `.template`, `.dist`) are left alone.

A value printed once is in the transcript for good, so this refuses before the
call runs. What stays allowed never prints a value: `cp`, `mv`, `cmp`,
`diff -q`, `ls`, `source`, `curl -n`, `git status/add/rm/check-ignore/ls-files`,
`grep -l/-L/-q/-c`, and the key-name forms `grep -oE '^[A-Za-z_]…'`,
`cut -d= -f1` and `sed 's/=.*//'`. Any other command that names one of these
files is refused; a denylist of printing commands would always be one short.

## check-bare-references.sh

`Stop`. Refuses to end a turn whose reply uses a reference without saying what
it is: an F-number from a held-back list, an answer code (`1b`), a GSD decision
id (`D-18`) or a requirement id (`ASGN-06`). Explained means followed by its
description (`F17.`, `F17:`, `F17 —`, `F17 (…`, `D-18 is the …`), a list line
starting with it, or sitting in parentheses after one. Code is ignored. Jira
keys are not checked.

Answer codes only count in a sentence about answers or options, or with a
second code beside them, so "a 3d model" is left alone.

## Install

Needs `curl`, `tar` and `jq`. From the newest release:

    v=$(curl -fsSL https://raw.githubusercontent.com/lenny1882/claude-hooks/versions/versions.txt | awk '$1=="claude-guard-hooks" {print $2}')
    curl -fsSL "https://github.com/lenny1882/claude-hooks/releases/download/claude-guard-hooks-v$v/claude-guard-hooks.tar.gz" | tar -xz
    cd claude-guard-hooks && ./install.sh

These lines never change between versions: `versions.txt` names the newest
stable release, and only once its tarball is uploaded. To pin a version,
download `.../releases/download/claude-guard-hooks-vX.Y.Z/claude-guard-hooks.tar.gz` instead.

Or from a clone of the whole repo:

    git clone https://github.com/lenny1882/claude-hooks && cd claude-hooks/packages/claude-guard-hooks
    ./install.sh              # install
    ./install.sh --link       # or symlink, so edits in the checkout are live
    ./install.sh --dry-run    # show the settings change, write nothing
    ./install.sh --yes        # no prompts

Re-running the installer is safe and is how you upgrade. It merges into
`settings.json` rather than replacing it, backs the file up first, and only ever
touches its own entries. If Claude Code is already running, `/hooks` forces a
settings reload.

It touches only its own nine entries — other hooks, including
`claude-branch-guard`'s, are left alone, and there is a test for exactly that. A
newly registered hook needs a Claude Code restart; `/hooks` only reloads changes
to existing ones.

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

Feeds each hook the JSON Claude Code would send and checks the decision — both
event shapes for `check-discuss-batch.sh`, the four replies corrected on
26 Oct 2026 for `check-write-handoff.sh`, and the prose that must not set off
`redirect-blocked-write.sh` — then exercises the installer against
a throwaway settings file.

## Releasing

`/release claude-guard-hooks` at the repo root — bump `packages/claude-guard-hooks/VERSION` on `main`,
move `release/claude-guard-hooks-vX.x` onto it, tag `claude-guard-hooks-vX.Y.Z` there. The tag is what
publishes it. The release carries what `PAYLOAD` lists, and nothing else in
this directory.
