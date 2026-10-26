#!/usr/bin/env bash
# Daily release check for claude-guard-hooks.
#
# Asks the release lookup below what the newest release is, compares it
# against the version recorded at install time, and writes the answer to a
# state file. It never fetches, never touches the install directory, and never
# installs anything — upgrading is always an explicit `./update.sh`.
#
# A release left as a draft or marked pre-release is never reported, no
# matter how its version number sorts. update.sh downloads that release's
# claude-guard-hooks.tar.gz asset directly — no git involved, so this works the same
# whether the install came from a git clone or a downloaded tarball.
#
# The check runs at most once per calendar day. Callers should run it in the
# background: a remote that is unreachable, slow, or asking for credentials
# must never hold up a session. `curl` is invoked under `timeout` for exactly
# that reason, and the day stamp is written even when the check fails, so an
# offline machine tries once a day rather than every session.
#
# Needs `curl`.
#
# Everything a caller displays comes from the *previous* run's state file. That
# is deliberate: reading a file is instant, whereas waiting on the network is
# not, so the notice you see is at most a day stale and costs nothing to show.
#
#   check [--force]   run today's check if it has not run; silent; ~0.5s
#   badge             "<glyph> vX.Y.Z" if an update is waiting, else nothing
#   notice            two-line plain-text notice, else nothing
#   hook-json         {"systemMessage": "..."} for a hook to emit, else nothing
#   status            installed / available / last checked
#   record-install <version> <repo-dir>    called by install.sh
#   clear             forget what the last check found

set -uo pipefail

PROJECT="claude-guard-hooks"
DISPLAY_NAME="claude-guard-hooks"
GITHUB_SLUG="lenny1882/claude-hooks"
CURL=(timeout 8 curl)

STATE="${XDG_STATE_HOME:-$HOME/.local/state}/$PROJECT"
STAMP="$STATE/last-check"
AVAIL="$STATE/available"
URL_F="$STATE/available-url"
INSTALLED="$STATE/installed"
REPO_F="$STATE/repo-dir"

read_file() { cat "$1" 2>/dev/null | head -1 | tr -d '[:space:]'; }

# True when $2 is a strictly higher version than $1. sort -V orders 1.9.0
# below 1.10.0, which a string comparison would get backwards.
newer_than() {
  [ -n "$2" ] || return 1
  [ "$1" = "$2" ] && return 1
  [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" = "$2" ]
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

update_pending() {
  local have want
  have=$(read_file "$INSTALLED"); want=$(read_file "$AVAIL")
  [ -n "$have" ] || return 1
  newer_than "$have" "$want"
}

# --- the check itself --------------------------------------------------------

do_check() {
  local repo tag latest rel_url lookup_error
  mkdir -p "$STATE"

  repo=$(read_file "$REPO_F")
  # No recorded install, or it has been moved or deleted: nothing to ask.
  [ -n "$repo" ] && [ -d "$repo" ] || return 0

  # Stamp first. A remote that hangs or refuses should cost one attempt per
  # day, not one per session start.
  date +%F > "$STAMP"

  if ! release_lookup; then
    : > "$AVAIL"; : > "$URL_F"
    return 0
  fi

  printf '%s\n' "$latest" > "$AVAIL"
  printf '%s\n' "$rel_url" > "$URL_F"
}

checked_today() {
  [ "$(read_file "$STAMP")" = "$(date +%F)" ]
}

# --- subcommands -------------------------------------------------------------

case "${1:-status}" in
  check)
    if [ "${2:-}" != "--force" ] && checked_today; then exit 0; fi
    do_check
    ;;

  badge)
    update_pending && printf '⬆ v%s' "$(read_file "$AVAIL")"
    ;;

  notice)
    if update_pending; then
      printf '%s: v%s is available (installed: v%s)\n' \
        "$PROJECT" "$(read_file "$AVAIL")" "$(read_file "$INSTALLED")"
      printf '  update with: cd %s && ./update.sh\n' "$(read_file "$REPO_F")"
      url=$(read_file "$URL_F")
      [ -n "$url" ] && printf '  release notes: %s\n' "$url"
    fi
    ;;

  hook-json)
    if update_pending; then
      msg=$(printf '%s v%s is available (you have v%s). Update: cd %s && ./update.sh' \
        "$DISPLAY_NAME" "$(read_file "$AVAIL")" "$(read_file "$INSTALLED")" "$(read_file "$REPO_F")")
      if command -v jq >/dev/null 2>&1; then
        jq -n --arg m "$msg" '{systemMessage: $m}'
      else
        # Only the message is interpolated and it is built from version strings
        # and a path, so escaping quotes and backslashes covers it.
        printf '{"systemMessage": "%s"}\n' "$(printf '%s' "$msg" | sed 's/\\/\\\\/g; s/"/\\"/g')"
      fi
    fi
    ;;

  status)
    printf '%s\n' "$DISPLAY_NAME"
    printf '  installed:    %s\n' "$(read_file "$INSTALLED" || true)"
    printf '  available:    %s\n' "$(read_file "$AVAIL" | grep . || echo '(none found)')"
    printf '  release url:  %s\n' "$(read_file "$URL_F" | grep . || echo '-')"
    printf '  last checked: %s\n' "$(read_file "$STAMP" | grep . || echo 'never')"
    printf '  repo:         %s\n' "$(read_file "$REPO_F" | grep . || echo '(not recorded)')"
    update_pending && printf '  -> update available, run ./update.sh in the repo\n'
    ;;

  record-install)
    mkdir -p "$STATE"
    printf '%s\n' "${2:?version required}"  > "$INSTALLED"
    printf '%s\n' "${3:?repo dir required}" > "$REPO_F"
    ;;

  clear)
    rm -f "$STAMP" "$AVAIL" "$URL_F"
    ;;

  *)
    printf 'usage: %s {check [--force]|badge|notice|hook-json|status|clear}\n' \
      "$(basename "$0")" >&2
    exit 1
    ;;
esac
exit 0
