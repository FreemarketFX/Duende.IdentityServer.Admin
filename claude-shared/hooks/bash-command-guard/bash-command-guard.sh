#!/usr/bin/env bash
# PreToolUse Bash command-guard (*nix).
#
# Reads PreToolUse JSON from stdin, extracts tool_input.command, and matches
# it against `blocklist.txt` and `warnlist.txt` in this directory. Each list
# entry is a regex (case-insensitive). First block-list match -> exit 2 with
# stderr message + sentinel. First warn-list match -> exit 0, log warn only.
#
# Telemetry is best-effort via the shared Datadog helper. Set
# BASH_GUARD_NO_LOG=1 to suppress (used by test-guard.sh). Set
# BASH_GUARD_TEST_MODE=1 to suppress all stderr output and instead print
# "<outcome>\t<pattern>" to stdout (used by test-guard.sh runner).
#
# Defensive ERR trap. Mirrors the elevation-guard pattern; only fires under
# `set -e`, which we deliberately do not enable (errexit on a hook that runs
# on every Bash call would be a bigger foot-gun than the rare untrapped
# error). Kept as a belt for future maintainers who may add `set -e`.

trap 'exit 0' ERR

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
[ -z "$script_dir" ] && exit 0

blocklist_path="$script_dir/blocklist.txt"
warnlist_path="$script_dir/warnlist.txt"

# Read PreToolUse stdin payload (best-effort).
payload=""
if [ ! -t 0 ]; then payload="$(cat || true)"; fi

# Extract tool_name and tool_input.command. Prefer python3, fall back to jq,
# fall back to a sed best-effort. If we can't parse the command, exit 0
# (fail open) — better to miss a block than to wedge Bash.
tool_name="unknown"
command_text=""

if [ -n "$payload" ]; then
  if python3 -c 'pass' >/dev/null 2>&1; then
    extracted="$(STDIN_JSON="$payload" python3 - <<'PY' 2>/dev/null
import json, os, sys
try:
    p = json.loads(os.environ.get('STDIN_JSON', '') or '{}')
    tn = str(p.get('tool_name', '') or '')
    cmd = str((p.get('tool_input') or {}).get('command', '') or '')
    sys.stdout.write(tn + '\x1f' + cmd)
except Exception:
    pass
PY
)"
    if [ -n "$extracted" ]; then
      tool_name="${extracted%%$'\x1f'*}"
      command_text="${extracted#*$'\x1f'}"
    fi
  elif jq --version >/dev/null 2>&1; then
    # `|| true` so a malformed-JSON jq exit doesn't propagate non-zero out
    # of the command substitution — the ERR trap would catch it and we'd
    # exit before the short-circuit/test-marker path runs.
    tool_name="$(printf '%s' "$payload" | jq -r '.tool_name // ""' 2>/dev/null || true)"
    command_text="$(printf '%s' "$payload" | jq -r '.tool_input.command // ""' 2>/dev/null || true)"
  else
    # sed best-effort. Fragile for embedded quotes — acceptable as last resort.
    tool_name="$(printf '%s' "$payload" | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1 || true)"
    command_text="$(printf '%s' "$payload" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\(.*\)"[[:space:]]*[,}].*/\1/p' | head -n1 || true)"
  fi
fi

[ -z "$tool_name" ] && tool_name="unknown"

# Helper: in test mode, emit the allow marker before any short-circuit exit
# so the test runner can distinguish "exit 0 because not Bash" from a bug
# that returned no output at all.
emit_test_allow_and_exit() {
  if [ "${BASH_GUARD_TEST_MODE:-0}" = "1" ]; then
    printf 'allow\t\n'
  fi
  exit 0
}

# Only inspect Bash calls. The hook is registered with a Bash matcher, but
# defense-in-depth in case the matcher is ever broadened.
if [ "$tool_name" != "Bash" ]; then emit_test_allow_and_exit; fi
if [ -z "$command_text" ]; then emit_test_allow_and_exit; fi

# Read a list file (regexes; # comments and blank lines stripped) into the
# named array variable via bash 4.3+ nameref. Bad regexes are skipped at
# match time (see match_any).
load_list() {
  local list_path="$1" line
  local -n arr="$2"
  [ -r "$list_path" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line#"${line%%[![:space:]]*}"}"   # ltrim
    line="${line%"${line##*[![:space:]]}"}"   # rtrim
    [ -z "$line" ] && continue
    case "$line" in \#*) continue ;; esac
    arr+=("$line")
  done < "$list_path"
}

block_patterns=()
warn_patterns=()
load_list "$blocklist_path" block_patterns
load_list "$warnlist_path"  warn_patterns

# Case-insensitive regex match. Returns 0 on hit and writes matched pattern
# to $matched_pattern, 1 otherwise. A bad regex line will emit a one-line
# parse error to stderr — accepted as a dev-time signal, since the test
# matrix exercises every shipped pattern and would catch it before merge.
matched_pattern=""
match_any() {
  local cmd="$1"; shift
  local pat
  shopt -s nocasematch
  for pat in "$@"; do
    if [[ "$cmd" =~ $pat ]]; then
      matched_pattern="$pat"
      shopt -u nocasematch
      return 0
    fi
  done
  shopt -u nocasematch
  return 1
}

# Truncate the command for log preview (avoid leaking secrets).
preview="${command_text:0:200}"

emit_dd_log() {
  local outcome="$1" reason="$2" status="$3" message="$4" event_name="$5"
  [ "${BASH_GUARD_NO_LOG:-0}" = "1" ] && return 0

  # Build EXTRA_JSON with the full command under `source.command` for
  # triage parity with prompt-defender. Prefer python3 (universally
  # available where the helper itself runs); fall back to jq.
  local extra_json=""
  if python3 -c 'pass' >/dev/null 2>&1; then
    extra_json="$(CMD="$command_text" PAT="$matched_pattern" python3 -c '
import json, os
print(json.dumps({"source": {"tool": "Bash", "command": os.environ.get("CMD",""), "matched_pattern": os.environ.get("PAT","")}}))
' 2>/dev/null || true)"
  elif jq --version >/dev/null 2>&1; then
    extra_json="$(jq -nc --arg c "$command_text" --arg p "$matched_pattern" \
      '{source: {tool: "Bash", command: $c, matched_pattern: $p}}' 2>/dev/null || true)"
  fi

  # shellcheck disable=SC1091
  . "$script_dir/../lib/datadog-log/post.sh" 2>/dev/null || return 0
  HOOK=bash-command-guard \
  HOOK_EVENT=PreToolUse \
  TOOL_NAME=Bash \
  OUTCOME="$outcome" \
  REASON="$reason" \
  STATUS="$status" \
  MESSAGE="$message" \
  EVENT_NAME="$event_name" \
  STDIN_JSON="$payload" \
  EXTRA_JSON="$extra_json" \
    send_datadog_hook_log 2>/dev/null || true
}

if match_any "$command_text" "${block_patterns[@]}"; then
  human="Blocked: Bash command matched guard pattern '$matched_pattern'. Report this in #tech-claude-faq if you need assistance. DO NOT ATTEMPT TO CIRCUMVENT OR BYPASS THIS CONTROL."
  message="$human Command preview: $preview"
  # Emit DD log first so test mode + --with-logging surfaces it. The
  # helper self-checks BASH_GUARD_NO_LOG and is fail-open.
  emit_dd_log block blocklist_match error "$message" hook_block
  if [ "${BASH_GUARD_TEST_MODE:-0}" = "1" ]; then
    printf 'block\t%s\n' "$matched_pattern"
    exit 2
  fi
  sentinel="CLAUDE_BASH_GUARD_BLOCK pattern=$matched_pattern tool=Bash pid=$$"
  printf '%s\n%s\n' "$human" "$sentinel" 1>&2
  exit 2
fi

if match_any "$command_text" "${warn_patterns[@]}"; then
  message="Warn: Bash command matched warn pattern '$matched_pattern'. Command preview: $preview"
  emit_dd_log warn warnlist_match warning "$message" hook_warn
  if [ "${BASH_GUARD_TEST_MODE:-0}" = "1" ]; then
    printf 'warn\t%s\n' "$matched_pattern"
    exit 0
  fi
  exit 0
fi

if [ "${BASH_GUARD_TEST_MODE:-0}" = "1" ]; then
  printf 'allow\t\n'
fi
exit 0
