#!/usr/bin/env bash
# Update handoff-gate to its newest release, then re-run the installer.
#
# "Newest" is whatever the release lookup below reports; a draft or a
# pre-release is never offered, no matter how its version number sorts. This
# downloads that release's handoff-gate.tar.gz asset and extracts it over this
# directory, so it works the same whether you installed from a downloaded
# tarball or a git clone — no git required.
#
#   ./update.sh            check, ask, upgrade, reinstall
#   ./update.sh --check    report what is available and stop
#   ./update.sh --yes      no prompts (the reinstall inherits this)
#
# Any other options are passed straight through to install.sh, so
# `./update.sh --link` upgrades a symlinked development install.
#
# Needs `curl` and `tar`.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="handoff-gate"
GITHUB_SLUG="lenny1882/claude-hooks"
TARBALL_NAME="handoff-gate.tar.gz"
CURL=(curl)

[ -f "$REPO/VERSION" ] || {
  printf '%s does not look like a %s install (no VERSION file).\n' "$REPO" "$PROJECT" >&2
  exit 1
}
CURRENT="$(head -1 "$REPO/VERSION" | tr -d '[:space:]')"

CHECK_ONLY=0; ASSUME_YES=0; PASSTHROUGH=()
for a in "$@"; do
  case "$a" in
    --check)   CHECK_ONLY=1 ;;
    --yes|-y)  ASSUME_YES=1; PASSTHROUGH+=("$a") ;;
    -h|--help) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)         PASSTHROUGH+=("$a") ;;
  esac
done

say()  { printf '%s\n' "$*"; }
die()  { printf '%s\n' "$*" >&2; exit 1; }

confirm() {
  [ "$ASSUME_YES" -eq 1 ] && return 0
  local reply
  read -r -p "$1 [Y/n] " reply </dev/tty || return 1
  case "$reply" in [Nn]*) return 1 ;; *) return 0 ;; esac
}

# --- release lookup: versions.txt on the versions branch ---------------------
# new-package.sh inserts this for a package in a monorepo. There,
# /releases/latest returns whichever package released last, so the repo's
# release workflow keeps one line per package — "<name> <version>" — in
# versions.txt on the versions branch. It writes a package's line only after
# that release's tarball is uploaded, and never for a pre-release, so the file
# never names a version that cannot be downloaded.
#
# release_lookup sets tag, latest and rel_url, or returns 1 with the reason in
# lookup_error. It runs curl as "${CURL[@]}", so a caller can wrap it in
# `timeout`. VERSIONS_URL can be overridden, which is how tests run it against
# a local file.

VERSIONS_URL="${VERSIONS_URL:-https://raw.githubusercontent.com/$GITHUB_SLUG/versions/versions.txt}"

release_lookup() {
  local list
  tag=""; latest=""; rel_url=""; lookup_error=""

  list=$("${CURL[@]}" -fsSL "$VERSIONS_URL" 2>/dev/null) \
    || { lookup_error="Could not read $VERSIONS_URL — no release published yet, or no network."; return 1; }

  latest=$(printf '%s\n' "$list" | awk -v p="$PROJECT" '$1 == p { print $2; exit }' \
    | grep -E '^[0-9]+(\.[0-9]+)*$') || true
  [ -n "$latest" ] || { lookup_error="$VERSIONS_URL lists no release of $PROJECT yet."; return 1; }

  tag="$PROJECT-v$latest"
  rel_url="https://github.com/$GITHUB_SLUG/releases/tag/$tag"
}

say "== $PROJECT — installed v$CURRENT"
say "   asking github.com/$GITHUB_SLUG for the newest release"

release_lookup || die "$lookup_error"

# sort -V puts 1.10.0 above 1.9.0, which a string comparison gets backwards.
if [ "$latest" = "$CURRENT" ] \
   || [ "$(printf '%s\n%s\n' "$CURRENT" "$latest" | sort -V | tail -1)" = "$CURRENT" ]; then
  say "   already on the newest release (latest: v$latest)"
  exit 0
fi

say
say "   v$latest is available."
[ -n "$rel_url" ] && say "   release notes: $rel_url"
say

if [ "$CHECK_ONLY" -eq 1 ]; then
  say "   --check given; stopping here. Run without it to upgrade."
  exit 0
fi

confirm "   Update now?" || { say "   Left alone."; exit 0; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
asset_url="https://github.com/$GITHUB_SLUG/releases/download/$tag/$TARBALL_NAME"
say "   downloading $TARBALL_NAME (v$latest)"
curl -fsSL -o "$tmp/$TARBALL_NAME" "$asset_url" \
  || die "Could not download $asset_url"

say "   extracting into $REPO"
tar -xzf "$tmp/$TARBALL_NAME" -C "$REPO" --strip-components=1

say "   now at v$latest"
say
say "== Re-running the installer"
"$REPO/install.sh" "${PASSTHROUGH[@]+"${PASSTHROUGH[@]}"}"
