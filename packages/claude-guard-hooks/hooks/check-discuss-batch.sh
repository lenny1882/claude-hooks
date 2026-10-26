#!/bin/bash
# Stops /gsd:discuss-phase (and the /bm: equivalent) from running
# one-question-at-a-time by accident. Registered on two events, because there
# are two ways to start it and they take completely different routes:
#
#   PreToolUse (matcher Skill)   Claude calls the skill. Hooks can't prompt the
#                                terminal, so this denies the call and asks
#                                Claude to put the choice to the user.
#
#   UserPromptExpansion          The user types /gsd:discuss-phase. That never
#                                becomes a Skill tool call, so PreToolUse never
#                                sees it. Blocking here sets shouldQuery: false
#                                — Claude is not invoked at all — so the message
#                                is written to the user, not to Claude, and the
#                                only useful thing to say is what to retype.
#
# The flag is --batch / --batch=N (batch.md), not --batched.
#
# Skipped when the args already carry --batch, when --auto or --power is
# present (batch is a no-op in those modes, per modes/auto.md), and when
# --no-batch is passed as a deliberate one-off opt-out. GSD ignores the
# unrecognised --no-batch flag; it exists only for this hook.

command -v jq >/dev/null || exit 0   # fail open

input=$(cat)
event=$(printf '%s' "$input" | jq -r '.hook_event_name // empty')

# True when the argument string already settles how questions get asked.
has_flag() {
  case "$1" in
    *--batch*|*--no-batch*|*--auto*|*--power*) return 0 ;;
    *) return 1 ;;
  esac
}

case "$event" in

  UserPromptExpansion)
    name=$(printf '%s' "$input" | jq -r '.command_name // empty')
    args=$(printf '%s' "$input" | jq -r '.command_args // empty')
    prompt=$(printf '%s' "$input" | jq -r '.prompt // empty')

    # command_name is the name Claude Code resolved. Fall back to the first
    # word of the prompt if it is ever absent — prompt is built as
    # "/<name> <args>", so the first word is always the command.
    [ -n "$name" ] || { first=${prompt%% *}; name=$first; }
    name=${name#/}          # drop a leading slash
    name=${name##*:}        # drop a gsd: / bm: prefix

    [ "$name" = "discuss-phase" ] || exit 0
    has_flag "$args" && exit 0

    cat >&2 <<'MSG'
discuss-phase without a batching flag asks one question per turn.

Re-run it with one of:
  --batch      2-5 related questions per turn (recommended)
  --batch=3    fixed groups of 3
  --no-batch   one at a time, the stock flow
MSG
    exit 2
    ;;

  *)
    skill=$(printf '%s' "$input" | jq -r '.tool_input.skill // empty')
    args=$(printf '%s' "$input" | jq -r '.tool_input.args // empty')

    case "$skill" in
      gsd:discuss-phase|bm:discuss-phase) ;;
      *) exit 0 ;;
    esac
    has_flag "$args" && exit 0

    jq -n --arg skill "$skill" --arg args "$args" \
      '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: ("\($skill) was called without --batch (args: \"\($args)\"), so it would ask one question per turn. Do not re-run it yet. Use AskUserQuestion to ask the user how they want the questions asked, with these options: (1) --batch — 2-5 related questions per turn, recommended; (2) --batch=3 — fixed groups of 3; (3) --no-batch — one question at a time, the stock flow. Then re-run \($skill) with the same arguments plus exactly the flag they chose, including --no-batch for option 3, which this hook treats as a deliberate opt-out and lets through.")}}'
    exit 0
    ;;
esac
