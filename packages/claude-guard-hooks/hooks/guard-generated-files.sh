#!/bin/bash
# PreToolUse hook (matcher: Edit|Write|MultiEdit|NotebookEdit|Bash) — denies a
# hand edit to a file a tool generates, and says to find and run the generator.
#
# Background. The rule has been written down three times — as a memory in
# mesh-relay-api (5 Aug 2026), again in hugoboss-runner-api (24 Aug), and in
# ~/.claude/CLAUDE.md (21 Oct) — and was still broken on 21 Oct, when a plan
# edited auto_route's routes.gr.dart by hand. build_runner did run in the
# sandbox; nobody had tried it. A memory only reaches the project it was
# written in, and a rule read at session start loses to "it's one line, I'll
# just add it" in the middle of a task. This refuses the edit itself.
#
# What counts as generated. Two tests, either is enough:
#  - the name: *.g.dart, *.gr.dart, *.freezed.dart, *.mocks.dart, *.pb.dart,
#    *.pb.go, *_pb2.py, and lock files (pubspec.lock, Podfile.lock,
#    package-lock.json, yarn.lock, pnpm-lock.yaml, go.sum, Cargo.lock,
#    poetry.lock, composer.lock, Gemfile.lock);
#  - the header: the first five lines of the file on disk, or of the content
#    being written, say "GENERATED CODE", "DO NOT EDIT", "DO NOT MODIFY",
#    "@generated", "auto-generated" or "Code generated … DO NOT EDIT".
#
# Why Bash too. A hook on one tool does not cover the job: denied an Edit, the
# next move is `sed -i` on the same file. Bash is checked for an in-place edit
# (sed -i, perl -i) or a redirect/tee into a generated name. Running the
# generator — build_runner, go mod tidy, npm install — writes these files too,
# and is exactly what should happen, so only those write forms are refused.

JQ=$(command -v jq || echo /usr/bin/jq)
[ -x "$JQ" ] || exit 0

input=$(cat)
tool=$(printf '%s' "$input" | "$JQ" -r '.tool_name // ""')

GEN_NAME='(\.g\.dart|\.gr\.dart|\.freezed\.dart|\.mocks\.dart|\.pb\.dart|\.pb\.go|_pb2\.py|(^|/)(pubspec\.lock|Podfile\.lock|package-lock\.json|yarn\.lock|pnpm-lock\.yaml|go\.sum|Cargo\.lock|poetry\.lock|composer\.lock|Gemfile\.lock))$'
GEN_HEAD='GENERATED CODE|DO NOT EDIT|DO NOT MODIFY|@generated|auto-generated|Code generated .* DO NOT EDIT'

deny() { # deny <path>
  "$JQ" -n --arg p "$1" '{
    systemMessage: ("Hand edit of " + $p + " refused: generated file"),
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: ("Refused: " + $p + " is a generated file, and generated files are never edited by hand.\n\nFind how it is generated and change the source the generator reads instead: the annotated class, route definitions, schema, @GenerateMocks list, pubspec.yaml or go.mod. Then run the generator, scoped to the outputs you need — for example `dart run build_runner build --delete-conflicting-outputs`, `go mod tidy`, `flutter pub get`, `npm install`.\n\n\"It cannot run here\" is a claim to test, not to assume. If you have tried and it genuinely cannot run, stop and tell the user exactly what blocks it. Do not hand-edit as a fallback.")
    }
  }'
  exit 0
}

case "$tool" in
  Edit|Write|MultiEdit|NotebookEdit)
    path=$(printf '%s' "$input" | "$JQ" -r '.tool_input.file_path // .tool_input.notebook_path // ""')
    [ -n "$path" ] || exit 0
    printf '%s' "$path" | grep -qE "$GEN_NAME" && deny "$path"
    [ -f "$path" ] && head -n 5 "$path" 2>/dev/null | grep -qiE "$GEN_HEAD" && deny "$path"
    printf '%s' "$input" | "$JQ" -r '.tool_input.content // ""' | head -n 5 \
      | grep -qiE "$GEN_HEAD" && deny "$path"
    ;;
  Bash)
    cmd=$(printf '%s' "$input" | "$JQ" -r '.tool_input.command // ""')
    set -f   # the command's words are split below; a * in it must not glob
    # Split on ; && || | and newlines so each piece is judged on its own.
    while IFS= read -r seg; do
      for word in $seg; do
        w=${word#[\'\"]}; w=${w%[\'\";]}
        printf '%s' "$w" | grep -qE "$GEN_NAME" || continue
        if printf '%s' "$seg" | grep -qE '(^|[[:space:]])(sed|perl)[[:space:]]+([^[:space:]]+[[:space:]]+)*-[a-zA-Z]*i' \
           || printf '%s' "$seg" | grep -qE "(>>?|tee( -a)?)[[:space:]]*['\"]?[^[:space:]]*$(printf '%s' "${w##*/}" | sed 's/[.]/\\./g')"; then
          deny "$w"
        fi
      done
    done < <(printf '%s\n' "$cmd" | sed -E 's/(\|\||&&|;|\|)/\n/g')
    ;;
esac
exit 0
