#!/usr/bin/env bash
# Test harness for bash-command-guard.sh.
#
# Default mode (no args):
#   Loads test-cases.json, runs every case through the hook, prints pass/fail
#   per case, exits non-zero if any case fails.
#
# Override mode:
#   ./test-guard.sh --command "<text>"        Run a single command, print outcome.
#   ./test-guard.sh --command "<text>" --with-logging  Same but emit DD log.
#
# DD logging is suppressed by default via BASH_GUARD_NO_LOG=1 so test runs
# don't pollute the dashboard.

set -u

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
hook_script="$script_dir/bash-command-guard.sh"
cases_path="$script_dir/test-cases.json"

with_logging=0
single_command=""
usage() {
  cat <<'EOF'
test-guard.sh — invoke bash-command-guard.sh with synthesized PreToolUse payloads.

  ./test-guard.sh                              Run the full test-cases.json matrix.
  ./test-guard.sh --command "<text>"           Run a single command, print outcome.
  ./test-guard.sh --command "<text>" --with-logging
                                               Same but emit Datadog log.

DD logging is suppressed by default via BASH_GUARD_NO_LOG=1.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --command)        single_command="${2:-}"; shift 2 ;;
    --with-logging)   with_logging=1; shift ;;
    -h|--help)        usage; exit 0 ;;
    *)
      echo "Unknown arg: $1" >&2; usage >&2; exit 2 ;;
  esac
done

# Build a synthesized PreToolUse payload for a given command (with optional
# tool_name override) and pipe it through the hook in test mode. If
# raw_payload is non-empty, send it verbatim instead. Echoes
# "<outcome>\t<pattern>|<exit-code>".
run_one() {
  local cmd="$1" tool_name="${2:-Bash}" raw_payload="${3:-}"

  local payload
  if [ -n "$raw_payload" ]; then
    payload="$raw_payload"
  elif python3 -c 'pass' >/dev/null 2>&1; then
    payload="$(CMD="$cmd" TN="$tool_name" python3 -c 'import json,os; print(json.dumps({"tool_name":os.environ["TN"],"tool_input":{"command":os.environ["CMD"]}}))')"
  elif jq --version >/dev/null 2>&1; then
    payload="$(jq -nc --arg c "$cmd" --arg t "$tool_name" '{tool_name:$t,tool_input:{command:$c}}')"
  else
    echo "test-guard: need python3 or jq" >&2; exit 2
  fi

  local out exit_code
  out="$(BASH_GUARD_TEST_MODE=1 BASH_GUARD_NO_LOG=$([ "$with_logging" = "1" ] && echo 0 || echo 1) \
        bash "$hook_script" <<<"$payload" 2>/dev/null)"
  exit_code=$?
  printf '%s|%s' "$out" "$exit_code"
}

if [ -n "$single_command" ]; then
  result="$(run_one "$single_command")"
  body="${result%|*}"
  rc="${result##*|}"
  outcome="${body%%$'\t'*}"
  pattern="${body#*$'\t'}"
  case "$outcome" in
    block) printf 'BLOCKED  pattern=%s  exit=%s\n' "$pattern" "$rc" ;;
    warn)  printf 'WARNED   pattern=%s  exit=%s\n' "$pattern" "$rc" ;;
    allow) printf 'ALLOWED                exit=%s\n' "$rc" ;;
    *)     printf 'UNKNOWN  body=%s     exit=%s\n' "$body" "$rc" ;;
  esac
  exit 0
fi

# Default: run full matrix.
if [ ! -r "$cases_path" ]; then
  echo "test-cases.json not found at $cases_path" >&2; exit 2
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "test-guard: jq is required for the test matrix runner" >&2; exit 2
fi

pass=0; fail=0
total="$(jq 'length' "$cases_path")"
echo "Running $total cases..."
echo

idx=0
while IFS= read -r row; do
  idx=$((idx+1))
  cmd="$(jq -r '.command // ""' <<<"$row")"
  expected="$(jq -r '.expected' <<<"$row")"
  expected_pattern="$(jq -r '.pattern // ""' <<<"$row")"
  case_tool_name="$(jq -r '.tool_name // "Bash"' <<<"$row")"
  case_raw_payload="$(jq -r '.raw_payload // ""' <<<"$row")"
  case_label="$(jq -r '.label // .command // .raw_payload // ""' <<<"$row")"

  result="$(run_one "$cmd" "$case_tool_name" "$case_raw_payload")"
  body="${result%|*}"
  actual_outcome="${body%%$'\t'*}"
  actual_pattern="${body#*$'\t'}"

  if [ "$actual_outcome" = "$expected" ]; then
    if [ "$expected" = "allow" ] || [ -z "$expected_pattern" ] || [ "$actual_pattern" = "$expected_pattern" ]; then
      pass=$((pass+1))
      printf '  [PASS] %s -> %s%s\n' "$case_label" "$actual_outcome" \
        "$([ "$actual_outcome" != "allow" ] && printf ' (%s)' "$actual_pattern" || true)"
    else
      fail=$((fail+1))
      printf '  [FAIL] %s -> %s but matched %s, expected pattern %s\n' \
        "$case_label" "$actual_outcome" "$actual_pattern" "$expected_pattern"
    fi
  else
    fail=$((fail+1))
    printf '  [FAIL] %s -> got %s%s, expected %s%s\n' \
      "$case_label" "$actual_outcome" \
      "$([ "$actual_outcome" != "allow" ] && printf ' (%s)' "$actual_pattern" || true)" \
      "$expected" \
      "$([ -n "$expected_pattern" ] && [ "$expected_pattern" != "null" ] && printf ' (%s)' "$expected_pattern" || true)"
  fi
done < <(jq -c '.[]' "$cases_path")

echo
echo "Results: $pass passed, $fail failed (of $total)"
[ "$fail" -eq 0 ]
