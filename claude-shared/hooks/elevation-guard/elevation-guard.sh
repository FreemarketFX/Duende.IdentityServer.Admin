#!/usr/bin/env bash
# PreToolUse elevation guard (*nix).
#
# Blocks any tool call when Claude Code is running as root (uid 0).
# On block: emits two stderr lines and exits 2 (Claude Code contract:
# PreToolUse exit 2 = deny + feed stderr to Claude / OTEL log).
#
#   1. Human-readable block reason (relayed by Claude to the user).
#   2. Stable, greppable OTEL sentinel:
#      CLAUDE_ELEVATION_BLOCK tool=<TOOL> user=<USER> os=<OS> pid=<PID>
#
# Fails open (exit 0) on any unexpected error.

# Fail-open trap: any unhandled error leaves us with exit 0.
trap 'exit 0' ERR

# Best-effort tool_name extraction from PreToolUse stdin JSON. No jq dependency.
# Capture the full payload so the Datadog helper can mine session_id / cwd / etc.
tool_name="unknown"
payload=""
if [ ! -t 0 ]; then
  payload="$(cat || true)"
  if [ -n "$payload" ]; then
    extracted="$(printf '%s' "$payload" | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
    if [ -n "$extracted" ]; then tool_name="$extracted"; fi
  fi
fi

uid="$(id -u 2>/dev/null || echo -1)"
if [ "$uid" = "0" ]; then
  os_name="$(uname -s 2>/dev/null || echo unknown)"
  user_name="${USER:-$(id -un 2>/dev/null || echo root)}"
  human="Blocked: Claude Code is running as root ($user_name). Re-run Claude Code as a non-root user to proceed."
  sentinel="CLAUDE_ELEVATION_BLOCK tool=$tool_name user=$user_name os=$os_name pid=$$"
  printf '%s\n%s\n' "$human" "$sentinel" 1>&2

  # Side-channel Datadog log. Sourced helper fails open on its own; we still
  # guard the source/call with || true so a missing helper never blocks the exit.
  # shellcheck disable=SC1091
  . "$(dirname "$0")/../lib/datadog-log/post.sh" 2>/dev/null || true
  HOOK=elevation-guard \
  HOOK_EVENT=PreToolUse \
  TOOL_NAME="$tool_name" \
  OUTCOME=block \
  REASON=elevated_shell \
  MESSAGE="$human" \
  STDIN_JSON="$payload" \
    send_datadog_hook_log 2>/dev/null || true

  exit 2
fi

exit 0
