---
name: release
description: Cut a new release of one package in claude-hooks — bump packages/<package>/VERSION on main, move the matching release/<package>-vX.x branch onto it, and tag <package>-vX.Y.Z there so the GitHub Actions release workflow publishes it. Use when the user asks to cut, ship, or publish a new release/version of a package in this repo.
---

# Cutting a release of a package in claude-hooks

Every package under `packages/` is released on its own, with its own version,
its own tags (`<package>-vX.Y.Z`) and its own release branches
(`release/<package>-vX.x`). This skill releases one package per run.

[`.github/workflows/release.yml`](../../../.github/workflows/release.yml)
turns any pushed `<package>-vX.Y.Z` tag into a GitHub Release, then records the
version in `versions.txt` on the `versions` branch. It does **not** check which
branch the tag came from — a tag push and a branch push are separate events,
so the workflow can't tell. That guarantee is enforced here instead, by
process: **a release tag only ever gets created on its
`release/<package>-vX.x` branch, after that branch has been moved onto
`main`.** This skill is the only place that should create release tags in this
repo — follow it in order, and don't tag straight off `main` or anywhere else.

There is one release branch per package per major version.
`release/handoff-gate-v1.x` carries every `handoff-gate` `1.Y.Z` release.
Minor versions do not get their own branch.

Treat every push in this skill as something to confirm with the user first —
they're visible to anyone watching the repo, and the last step publishes a
public GitHub Release.

## 0. Which package

The package is the skill's argument: `/release handoff-gate`. It must be a
directory under `packages/` with a `VERSION` file. If no package was given, or
the name isn't one, list the directories under `packages/` and ask which —
don't pick one.

Below, `<pkg>` is that name.

## 1. Confirm `main` is ready to release

- `git status --porcelain` must be empty. If not, stop and ask whether to
  commit, stash, or discard those changes first — don't decide for the user.
- `git fetch origin`, then compare local `main` against `origin/main`. Pull
  if local is behind. If local has commits `origin/main` doesn't, that's
  expected — they're what's about to be released — but confirm that's really
  what the user wants shipped, e.g. with `git log origin/main..main`.
- Find the package's last release tag with
  `git tag --list '<pkg>-v*' --sort=-v:refname | head -1`, and read
  `git log <that tag>..main -- packages/<pkg>` as a sanity check that this
  package has actually changed. Commits to other packages don't count.

## 2. Bump the version and push to `main`

- Read `packages/<pkg>/VERSION` for the current version. Work out the new
  one — ask the user (patch/minor/major) if it isn't obvious from what's being
  released; there's no changelog to infer it from.
- Write the new version to `packages/<pkg>/VERSION` and commit as
  `Bump <pkg> to X.Y.Z`, matching the wording already in this repo's history.
- Confirm, then `git push origin main`.

## 3. Move the release branch onto the new commit

The release branch is `release/<pkg>-vX.x`, taking `X` from the new version's
major number and leaving the `x` literal.

Do this **without checking the branch out**. Checking it out and running
`git merge main` went wrong once: the merge reported "Already up-to-date",
the branch never moved, and the tag ended up on `main` — the exact thing this
skill exists to prevent. Run the commands one at a time and read the full
output of each; don't chain them or pipe them through anything that hides it.

- **New major line** (branch doesn't exist yet): `git branch release/<pkg>-vX.x main`.
- **Existing line**: confirm the move is a fast-forward, then make it.

  ```bash
  git merge-base --is-ancestor release/<pkg>-vX.x main   # exit 0 means fast-forward
  git fetch . main:release/<pkg>-vX.x                    # moves the branch, worktree untouched
  ```

  A non-zero exit from the first command means `release/<pkg>-vX.x` has
  commits `main` doesn't — it diverged some other way. Stop and ask rather
  than forcing it.
- Check the branch actually moved: `git log -1 --oneline release/<pkg>-vX.x`
  should show the version-bump commit.
- Confirm, then push the branch.

## 4. Tag on the release branch

- `git tag -a <pkg>-vX.Y.Z release/<pkg>-vX.x -m "<pkg> vX.Y.Z"` — annotated,
  and naming the branch explicitly so the tag can't attach to whatever happens
  to be checked out. Match the message convention of the existing tags; a repo
  with none yet has its convention set by the first one.
- A pre-release takes a suffix after the version: `<pkg>-vX.Y.Z-rc1`. The
  workflow publishes it as a pre-release and leaves `versions.txt` alone.
- Verify with `git branch --contains <pkg>-vX.Y.Z`; it must list
  `release/<pkg>-vX.x`.
- Confirm, then `git push origin <pkg>-vX.Y.Z`. This is the step that fires
  the release workflow.

## 5. Wrap up

- Point the user at the Actions run (`https://github.com/<owner>/<repo>/actions`)
  and, once it finishes, the published release
  (`https://github.com/<owner>/<repo>/releases/tag/<pkg>-vX.Y.Z`). Derive
  `<owner>/<repo>` from `git remote get-url origin`.
- For a stable release, check the run's last step reported
  `versions.txt now lists <pkg> X.Y.Z`. Until it does, installs and update
  checks still see the previous version.
