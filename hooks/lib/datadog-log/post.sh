# Datadog log helper for Claude Code hooks (*nix).
#
# Source this file from a hook script and call send_datadog_hook_log. The
# function reads its inputs from environment variables (HOOK, HOOK_EVENT,
# TOOL_NAME, OUTCOME, REASON, EVENT_NAME, STATUS, MESSAGE, STDIN_JSON),
# auto-fills the environment envelope (host, os, user, pid, session,
# claude_code.version, terminal, ddsource, ddtags base, event.timestamp),
# and POSTs the merged payload to the Datadog browser-intake endpoint.
#
# The Client Token is read from the sibling 'client-token' file. If the
# file is missing/empty, or curl is not on PATH, the function returns
# silently. JSON construction is delegated to python3 (preferred) or jq
# (fallback) — hand-rolled JSON escaping in shell is fragile (empty
# strings, embedded quotes, multiline values), and we'd rather emit
# nothing than emit malformed payloads. If neither python3 nor jq is
# present, the function returns silently.
#
# All errors are swallowed — telemetry must not wedge a hook.
#
# Required env vars: HOOK, HOOK_EVENT, TOOL_NAME, OUTCOME, REASON.
# Defaults: EVENT_NAME=hook_block, STATUS=warning, MESSAGE=auto-composed.
# Optional: EXTRA_JSON — a JSON object (string) merged into the top-level
# log body. Mirrors the PowerShell helper's `-Extra` hashtable. Used by
# hooks that want to attach structured fields (e.g. `source.command`)
# alongside the standard envelope. Invalid JSON is silently ignored.

send_datadog_hook_log() {
  (
    set +e

    : "${HOOK:?}" "${HOOK_EVENT:?}" "${OUTCOME:?}" "${REASON:?}" 2>/dev/null || return 0
    # TOOL_NAME is optional. SessionStart / Stop / Notification hooks have
    # no associated tool; callers pass '' or 'none' for that case and we
    # drop the :tool suffix from hook_name, plus null out the tool field.
    TOOL_NAME="${TOOL_NAME:-}"

    local script_dir token_path token
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
    [ -z "$script_dir" ] && return 0
    token_path="$script_dir/client-token"
    [ -r "$token_path" ] || return 0
    token="$(tr -d '\r\n[:space:]' < "$token_path" 2>/dev/null)"
    [ -n "$token" ] || return 0

    command -v curl >/dev/null 2>&1 || return 0
    # Pick a JSON builder. python3 is preferred (universally present on
    # standard Ubuntu/macOS dev hosts); jq is the fallback (common on dev
    # machines, less so on stripped containers). We probe by *executing*
    # rather than `command -v` because MSYS exposes a Microsoft Store stub
    # at /c/.../WindowsApps/python3 that satisfies command -v but exits
    # non-zero with stderr noise.
    local builder=''
    if python3 -c 'pass' >/dev/null 2>&1; then
      builder=python3
    elif jq --version >/dev/null 2>&1; then
      builder=jq
    else
      return 0
    fi

    local event_name="${EVENT_NAME:-hook_block}"
    local status="${STATUS:-warning}"
    local hook_name has_tool=0
    if [ -n "$TOOL_NAME" ] && [ "$TOOL_NAME" != "none" ]; then
      hook_name="${HOOK_EVENT}:${TOOL_NAME}"
      has_tool=1
    else
      hook_name="${HOOK_EVENT}"
    fi

    local os_type
    case "$(uname -s 2>/dev/null)" in
      Linux*)  os_type=linux ;;
      Darwin*) os_type=darwin ;;
      *)       os_type=unknown ;;
    esac
    local os_version host_name host_arch user_name terminal_type pid parent_pid timestamp
    os_version="$(uname -r 2>/dev/null || echo unknown)"
    host_name="$(hostname 2>/dev/null || echo unknown)"
    host_arch="$(uname -m 2>/dev/null || echo unknown)"
    user_name="${USER:-$(id -un 2>/dev/null || echo unknown)}"
    terminal_type="${TERM_PROGRAM:-${TERM:-unknown}}"
    pid=$$
    parent_pid="$(ps -o ppid= -p "$$" 2>/dev/null | tr -d ' ' || echo 0)"
    [ -z "$parent_pid" ] && parent_pid=0
    timestamp="$(date -u +%Y-%m-%dT%H:%M:%S.000Z 2>/dev/null || echo '')"

    # Email Claude Code is authenticated as. Lives at ~/.claude.json under
    # oauthAccount.emailAddress; that field is unique in the file so a sed
    # extract is safe without a JSON parser. Fall back to USER if it looks
    # like an email; null otherwise.
    local user_email=''
    if [ -r "$HOME/.claude.json" ]; then
      user_email="$(sed -n 's/.*"emailAddress"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$HOME/.claude.json" 2>/dev/null | head -n1)"
    fi
    if [ -z "$user_email" ] && [[ "$user_name" == *@* ]]; then
      user_email="$user_name"
    fi

    local message="${MESSAGE:-${HOOK} ${OUTCOME}ed ${hook_name} for ${user_email:-$user_name} (${REASON})}"
    local tags="hook:${HOOK},outcome:${OUTCOME},reason:${REASON},os.type:${os_type}"

    # Build the JSON via the chosen builder. Both branches produce the
    # same payload shape — robust against empty strings, embedded quotes,
    # multiline values, and unicode. Inputs flow through env vars / jq
    # --arg, never through shell-escaped string interpolation.
    local body=''
    if [ "$builder" = python3 ]; then
      body="$(
        HOOK="$HOOK" \
        HOOK_EVENT="$HOOK_EVENT" \
        TOOL_NAME="$TOOL_NAME" \
        HAS_TOOL="$has_tool" \
        OUTCOME="$OUTCOME" \
        REASON="$REASON" \
        EVENT_NAME="$event_name" \
        STATUS="$status" \
        MESSAGE="$message" \
        DDTAGS="$tags" \
        HOOK_NAME="$hook_name" \
        OS_TYPE="$os_type" \
        OS_VERSION="$os_version" \
        HOST_NAME="$host_name" \
        HOST_ARCH="$host_arch" \
        USER_NAME="$user_name" \
        USER_EMAIL="$user_email" \
        TERMINAL_TYPE="$terminal_type" \
        PID_VAL="$pid" \
        PARENT_PID_VAL="$parent_pid" \
        TIMESTAMP="$timestamp" \
        STDIN_JSON="${STDIN_JSON:-}" \
        EXTRA_JSON="${EXTRA_JSON:-}" \
        CLAUDE_CODE_VERSION="${CLAUDE_CODE_VERSION:-}" \
        python3 - 2>/dev/null <<'PY'
import json, os, sys

env = os.environ.get
stdin = env('STDIN_JSON', '') or ''
session_id = transcript_path = cwd = ''
if stdin:
    try:
        p = json.loads(stdin)
        session_id     = str(p.get('session_id', '') or '')
        transcript_path= str(p.get('transcript_path', '') or '')
        cwd            = str(p.get('cwd', '') or '')
    except Exception:
        pass

user_name = env('USER_NAME', '') or ''
user_email = env('USER_EMAIL', '') or None

body = {
    'service': 'claude-code',
    'ddsource': 'claude-code-hook',
    'ddtags': env('DDTAGS', ''),
    'status': env('STATUS', 'warning'),
    'message': env('MESSAGE', ''),
    'event': {
        'name': env('EVENT_NAME', 'hook_block'),
        'timestamp': env('TIMESTAMP', ''),
    },
    'hook': env('HOOK', ''),
    'hook_event': env('HOOK_EVENT', ''),
    'hook_name': env('HOOK_NAME', ''),
    'tool': (env('TOOL_NAME') or None) if env('HAS_TOOL', '0') == '1' else None,
    'outcome': env('OUTCOME', ''),
    'reason': env('REASON', ''),
    'os': {
        'type': env('OS_TYPE', 'unknown'),
        'version': env('OS_VERSION', 'unknown'),
    },
    'host': {
        'name': env('HOST_NAME', 'unknown'),
        'arch': env('HOST_ARCH', 'unknown'),
    },
    'user': {
        'email': user_email,
        'name': user_name,
    },
    'pid': int(env('PID_VAL', '0') or 0),
    'parent_pid': int(env('PARENT_PID_VAL', '0') or 0),
    'session': { 'id': session_id },
    'transcript_path': transcript_path,
    'cwd': cwd,
    'tool_input_size_bytes': len(stdin.encode('utf-8')),
    'claude_code': { 'version': env('CLAUDE_CODE_VERSION', '') },
    'terminal': { 'type': env('TERMINAL_TYPE', 'unknown') },
}

extra_raw = env('EXTRA_JSON', '') or ''
if extra_raw:
    try:
        extra = json.loads(extra_raw)
        if isinstance(extra, dict):
            body.update(extra)
    except Exception:
        pass

sys.stdout.write(json.dumps(body))
PY
      )"
    else
      # jq path. --arg passes everything as strings (jq does the escaping);
      # numerics are converted via tonumber. STDIN_JSON is passed as a
      # string and parsed inside the filter — `try fromjson catch null`
      # tolerates absent / malformed payload.
      body="$(
        jq -nc 2>/dev/null \
          --arg ddtags "$tags" \
          --arg status "$status" \
          --arg message "$message" \
          --arg event_name "$event_name" \
          --arg timestamp "$timestamp" \
          --arg hook "$HOOK" \
          --arg hook_event "$HOOK_EVENT" \
          --arg hook_name "$hook_name" \
          --arg tool "$TOOL_NAME" \
          --arg has_tool "$has_tool" \
          --arg outcome "$OUTCOME" \
          --arg reason "$REASON" \
          --arg os_type "$os_type" \
          --arg os_version "$os_version" \
          --arg host_name "$host_name" \
          --arg host_arch "$host_arch" \
          --arg user_name "$user_name" \
          --arg user_email "$user_email" \
          --arg terminal_type "$terminal_type" \
          --arg cc_version "${CLAUDE_CODE_VERSION:-}" \
          --arg pid_str "$pid" \
          --arg parent_pid_str "$parent_pid" \
          --arg stdin_json "${STDIN_JSON:-}" \
          --arg extra_json "${EXTRA_JSON:-}" '
            ($stdin_json | try fromjson catch null) as $p
            | ($extra_json | try fromjson catch null) as $extra
            | (if ($user_email | length) > 0 then $user_email else null end) as $email
            | ($stdin_json | utf8bytelength) as $stdin_size
            | ({
                service: "claude-code",
                ddsource: "claude-code-hook",
                ddtags: $ddtags,
                status: $status,
                message: $message,
                event: { name: $event_name, timestamp: $timestamp },
                hook: $hook,
                hook_event: $hook_event,
                hook_name: $hook_name,
                tool: (if $has_tool == "1" then $tool else null end),
                outcome: $outcome,
                reason: $reason,
                os: { type: $os_type, version: $os_version },
                host: { name: $host_name, arch: $host_arch },
                user: { email: $email, name: $user_name },
                pid: ($pid_str | tonumber? // 0),
                parent_pid: ($parent_pid_str | tonumber? // 0),
                session: { id: ($p.session_id // "") },
                transcript_path: ($p.transcript_path // ""),
                cwd: ($p.cwd // ""),
                tool_input_size_bytes: $stdin_size,
                claude_code: { version: $cc_version },
                terminal: { type: $terminal_type }
              } + (if ($extra | type) == "object" then $extra else {} end))
          '
      )"
    fi

    [ -n "$body" ] || return 0

    local url="https://browser-intake-datadoghq.eu/api/v2/logs?dd-api-key=${token}&ddsource=claude-code-hook&dd-evp-origin=claude-code-hook&dd-evp-origin-version=0.1.0"

    curl --max-time 2 -fsS -X POST "$url" \
      -H 'Content-Type: text/plain;charset=UTF-8' \
      -H 'Origin: https://claude-code-hook.local' \
      --data "$body" >/dev/null 2>&1

    return 0
  )
}
