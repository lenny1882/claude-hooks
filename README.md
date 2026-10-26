# claude-hooks

Claude Code hooks that stop something happening quietly that should involve a
person or a record: an unsandboxed command, a compaction with no handoff, an
install nobody wrote down.

Every package under `packages/` is versioned, released and installed on its
own. A fault in one says nothing about another, so each can be fixed and
shipped without touching the rest.

## Packages

| Package | What it does |
| --- | --- |
| [`claude-guard-hooks`](packages/claude-guard-hooks/) | Denies unsandboxed Bash calls and flagless `/gsd:discuss-phase`, so both go to a person |
| [`inventory-guard`](packages/inventory-guard/) | Stops a turn ending while something installed in the Claude config is missing from `INVENTORY.md` |
| [`handoff-gate`](packages/handoff-gate/) | Cancels `/compact` until the session has written an up-to-date handoff, then lets it through |
<!-- new-package.sh --monorepo adds a row above this line -->

## Install a package

Needs `curl`, `tar` and `jq`. Set `pkg` to a name from the table:

    pkg=<package>
    v=$(curl -fsSL https://raw.githubusercontent.com/lenny1882/claude-hooks/versions/versions.txt | awk -v p="$pkg" '$1 == p {print $2}')
    curl -fsSL "https://github.com/lenny1882/claude-hooks/releases/download/$pkg-v$v/$pkg.tar.gz" | tar -xz
    cd "$pkg" && ./install.sh

`versions.txt` lists each package's newest stable version. The release workflow
writes a package's line only after that release's tarball is uploaded, so the
lines above never change between versions and always fetch something that
exists. To pin a version instead:

    https://github.com/lenny1882/claude-hooks/releases/download/<package>-vX.Y.Z/<package>.tar.gz

Each package's own README has the same lines with its name filled in, and
covers updating and uninstalling.

## Tests

    ./test/run-tests.sh

Runs every package's own suite, one section each, and fails if any of them
does.

## Releasing

`/release <package>` in this repo — bump `packages/<package>/VERSION` on
`main`, move `release/<package>-vX.x` onto it, and tag `<package>-vX.Y.Z` there.
The tag is what publishes it. See `.claude/skills/release/SKILL.md`.

## Licence

MIT with the Commons Clause; see [`LICENSE`](LICENSE). You may use, copy,
change and share the code, but not sell it or sell a service whose value comes
mainly from it. Every copy, and every substantial part of one, must keep the
copyright notice crediting <https://github.com/lenny1882/claude-hooks>.
