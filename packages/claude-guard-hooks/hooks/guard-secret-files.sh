#!/bin/bash
# PreToolUse hook (matcher: Read|Bash) — denies printing a credential file:
# .env and its variants, .netrc, ~/.aws/credentials, SSH private keys, and
# Bruno environment files.
#
# Background. On 14 Oct 2026 a session printed a .env holding a live AWS key
# pair while comparing two files, then promised to stop "from now on". The
# user's answer: it should never have happened at all. Once a value is in a
# transcript it has left the machine; a memory written afterwards cannot take it
# back, and that memory (never-print-secret-files) only loads in mesh-data. So
# the refusal has to come before the call runs, in every project.
#
# What is still allowed. Comparing, copying and loading these files never
# prints a value, and neither does listing the key names: cp, mv, cmp, ls,
# stat, test, source/., curl -n, `git status/add/rm/check-ignore/ls-files`,
# `diff -q`, `grep -l/-L/-q/-c`, and the two key-name forms
# `grep -oE '^[A-Za-z_]…'` and `cut -d= -f1` / `sed 's/=.*//'`. Anything else
# that reads one of these files in a Bash command is refused — a denylist of
# printing commands would always be one command short.
#
# .env.example, .env.sample, .env.template and .env.dist are templates with no
# values in them, and are left alone.

JQ=$(command -v jq || echo /usr/bin/jq)
[ -x "$JQ" ] || exit 0

input=$(cat)
tool=$(printf '%s' "$input" | "$JQ" -r '.tool_name // ""')

SECRET='(^|/)(\.env(\.[A-Za-z0-9_-]+)?|\.netrc|credentials|id_(rsa|ed25519|ecdsa|dsa))$|/environments/[^/]+\.bru$'
TEMPLATE='\.env\.(example|sample|template|dist)$'

is_secret() { # is_secret <path>
  printf '%s' "$1" | grep -qE "$TEMPLATE" && return 1
  printf '%s' "$1" | grep -qE "$SECRET" || return 1
  # "credentials" alone is too common a word; only the AWS file counts.
  case "$1" in *credentials) case "$1" in *.aws/credentials) return 0;; *) return 1;; esac;; esac
  return 0
}

deny() { # deny <path>
  "$JQ" -n --arg p "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: ("Refused: this would print " + $p + ", a credential file. Its values must never appear in a transcript.\n\nTo see what it holds, list the key names only:\n  grep -oE '"'"'^[A-Za-z_][A-Za-z0-9_]*'"'"' " + $p + "\nTo compare or copy it, use cmp, diff -q or cp, and print only the result. To use it, source it or pass it with --env-file.")
    }
  }'
  exit 0
}

case "$tool" in
  Read)
    path=$(printf '%s' "$input" | "$JQ" -r '.tool_input.file_path // ""')
    is_secret "$path" && deny "$path"
    ;;
  Bash)
    cmd=$(printf '%s' "$input" | "$JQ" -r '.tool_input.command // ""')
    set -f
    while IFS= read -r seg; do
      hit=""
      for word in $seg; do
        w=${word#[\'\"<]}; w=${w%[\'\";]}
        is_secret "$w" && { hit=$w; break; }
      done
      [ -n "$hit" ] || continue
      # The command word: skip leading VAR=value assignments.
      first=""; second=""
      for word in $seg; do
        case "$word" in *=*) [ -z "$first" ] && continue;; esac
        if [ -z "$first" ]; then first=$word; else second=$word; break; fi
      done
      case "$first" in
        cp|mv|cmp|ls|stat|test|'['|source|.|rm|touch|chmod|mkdir|curl|docker) continue ;;
        git) case "$second" in status|add|rm|mv|check-ignore|ls-files) continue;; esac ;;
        diff) printf '%s' "$seg" | grep -qE '(^|[[:space:]])(-q|--brief)([[:space:]]|$)' && continue ;;
        grep|rg)
          printf '%s' "$seg" | grep -qE '(^|[[:space:]])-[a-zA-Z]*[lLqc][a-zA-Z]*([[:space:]]|$)' && continue
          printf '%s' "$seg" | grep -qE -- "-[a-zA-Z]*o[a-zA-Z]*[[:space:]]+['\"]\^\[A-Za-z_\]" && continue ;;
        cut) printf '%s' "$seg" | grep -qE -- "-d *['\"]?=['\"]?" && printf '%s' "$seg" | grep -qE -- '-f *1([[:space:]]|$)' && continue ;;
        sed) printf '%s' "$seg" | grep -qE "s/=\.\*//" && continue ;;
      esac
      deny "$hit"
    done < <(printf '%s\n' "$cmd" | sed -E 's/(\|\||&&|;)/\n/g')
    ;;
esac
exit 0
