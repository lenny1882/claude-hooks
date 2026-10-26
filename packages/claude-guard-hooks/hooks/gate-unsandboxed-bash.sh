#!/bin/bash
# PreToolUse hook (matcher: Bash) — blocks any Bash call asking to run outside
# the sandbox, and tells Claude to stop and ask.
#
# Background. Claude's built-in guidance is to retry unsandboxed as soon as a
# command looks like it failed for sandbox reasons, without asking. In auto mode
# nobody sees that decision: it goes to the auto-mode classifier. So the sandbox
# stops being a boundary and becomes a routing hint — wrong door, try the other.
#
# Why "deny" and not "ask". "ask" was tried first and does NOT work here. In auto
# mode the harness resolves an "ask" decision through the same classifier, which
# approved a test command silently. Only "deny" is beyond its reach.
#
# This is the second of two layers. The first is sandbox.allowUnsandboxedCommands
# set to false in settings.json, which makes the dangerouslyDisableSandbox
# parameter inert harness-side. That setting is the actual enforcement; this hook
# exists so the refusal arrives as a clear instruction ("ask the user") rather
# than as a puzzling sandbox failure Claude then has to diagnose.
#
# To genuinely allow an unsandboxed command: remove allowUnsandboxedCommands from
# settings.json (or set it true) and disable this hook. Both, deliberately — the
# point is that it takes a person.

JQ=$(command -v jq || echo /usr/bin/jq)
[ -x "$JQ" ] || exit 0   # no jq: fail open rather than break every Bash call

input=$(cat)

unsandboxed=$(printf '%s' "$input" | "$JQ" -r '.tool_input.dangerouslyDisableSandbox // false')
[ "$unsandboxed" = "true" ] || exit 0

cmd=$(printf '%s' "$input" | "$JQ" -r '.tool_input.command // ""')

"$JQ" -n --arg cmd "$cmd" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: ("Blocked: this asks to run OUTSIDE the sandbox.\n\n  " + $cmd + "\n\nRunning unsandboxed is disabled on this machine and you cannot approve it yourself. A sandbox denial is a boundary, not a routing hint — do not look for another way through it.\n\nStop and tell the user: what you were running, what the sandbox refused, and why you think it needs to be outside the sandbox. Let them decide.")
  },
  systemMessage: "Unsandboxed Bash call blocked by ~/.claude/hooks/gate-unsandboxed-bash.sh"
}'
