# Installer tests for inventory-guard, sourced by run-tests.sh.
#
# This file belongs to claude-package-kit: upgrade-package.sh replaces it when
# the kit's installer changes, so a hand edit here is merged at best. Put this
# package's own tests in run-tests.sh. Expects REPO, TMP, CLAUDE_DIR and the ok
# and no functions to be set already.

echo "sanity"
for f in "$REPO"/*.sh "$REPO"/hooks/*.sh "$REPO"/lib/*.sh; do
  [ -f "$f" ] || continue
  bash -n "$f" && ok "$(basename "$f") parses" || no "$(basename "$f") parses" "syntax error"
done
[ -s "$REPO/VERSION" ] && ok "VERSION is set" || no "VERSION is set" "empty or missing"

echo "installer"
# A pre-existing hook from some other package, to prove we leave it alone.
printf '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"someone-elses-thing"}]}]}}\n' \
  > "$CLAUDE_DIR/settings.json"

"$REPO/install.sh" --link --yes >"$TMP/out" 2>&1 \
  && ok "installs" || no "installs" "$(tail -5 "$TMP/out")"
grep -q "someone-elses-thing" "$CLAUDE_DIR/settings.json" \
  && ok "leaves other packages' entries alone" || no "leaves other packages' entries alone" "removed them"

before=$(jq -S . "$CLAUDE_DIR/settings.json")
"$REPO/install.sh" --link --yes >/dev/null 2>&1
[ "$before" = "$(jq -S . "$CLAUDE_DIR/settings.json")" ] \
  && ok "installing twice changes nothing" || no "installing twice changes nothing" "settings drifted"

"$REPO/install.sh" --dry-run >"$TMP/out" 2>&1
grep -q "dry run" "$TMP/out" && ok "--dry-run writes nothing" || no "--dry-run writes nothing" "$(tail -3 "$TMP/out")"

"$REPO/uninstall.sh" --yes >/dev/null 2>&1
grep -q "someone-elses-thing" "$CLAUDE_DIR/settings.json" \
  && ok "uninstall leaves other packages alone" || no "uninstall leaves other packages alone" "removed them"
jq -e --arg o "inventory-guard" '[.. | .command? // empty] | any(contains($o))' \
  "$CLAUDE_DIR/settings.json" >/dev/null 2>&1 \
  && no "uninstall removes our entries" "still registered" || ok "uninstall removes our entries"

echo "release tarball"
# Whether the release tarball is enough to install from — the one thing a git
# checkout can never tell you, because everything is present either way. CI
# builds it with git archive at the tag; this builds the same file list out of
# the checkout and installs it. A package in a monorepo keeps the list in its
# own PAYLOAD file, because the root's one workflow serves every package.
payload=""
if [ -f "$REPO/PAYLOAD" ]; then
  payload=$(cat "$REPO/PAYLOAD")
elif [ -f "$REPO/.github/workflows/release.yml" ]; then
  payload=$(sed -n 's/^ *"\$TAG" -- //p' "$REPO/.github/workflows/release.yml")
fi
if [ -f "$REPO/PAYLOAD" ] || [ -f "$REPO/.github/workflows/release.yml" ]; then
  [ -n "$payload" ] && ok "found the payload list" || no "found the payload list" "PAYLOAD empty, or no git archive line in the workflow"
  mkdir -p "$TMP/tarball/inventory-guard"
  ( cd "$REPO" && tar -cf - $payload ) | ( cd "$TMP/tarball/inventory-guard" && tar -xf - )
  CLAUDE_DIR="$TMP/tarball-claude" "$TMP/tarball/inventory-guard/install.sh" --yes >"$TMP/out" 2>&1 \
    && ok "a tarball install works" || no "a tarball install works" "$(tail -4 "$TMP/out")"
else
  ok "no release workflow to check (--no-release)"
fi
