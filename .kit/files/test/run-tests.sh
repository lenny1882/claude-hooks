#!/usr/bin/env bash
# Runs every package's own test suite, one section each, and fails if any of
# them does. Each suite redirects HOME and CLAUDE_DIR into its own temp
# directory, so nothing here touches the real config either.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

ran=0; failed=()
for suite in "$ROOT"/packages/*/test/run-tests.sh; do
  [ -f "$suite" ] || continue
  pkg=$(basename "$(dirname "$(dirname "$suite")")")
  printf '\n### %s\n' "$pkg"
  ran=$((ran+1))
  "$suite" || failed+=("$pkg")
done

if [ "$ran" -eq 0 ]; then
  printf 'no packages under %s/packages yet\n' "$ROOT"
  exit 0
fi

printf '\n%d packages, %d failed' "$ran" "${#failed[@]}"
[ "${#failed[@]}" -eq 0 ] && { printf '\n'; exit 0; }
printf ': %s\n' "${failed[*]}"
exit 1
