# datadog-log helper

Shared library for Claude Code hooks that need to emit a structured log to Datadog when they block, warn, or otherwise want observability beyond the OTEL `claude_code.hook_execution_complete` event.

Authentication is via a **Datadog Client Token** bundled in this directory at `client-token`.

## When to use it

The Claude Code OTEL exporter already emits `claude_code.hook_execution_complete` with `num_blocking>0` whenever any hook blocks, but the schema does not carry the hook command/script identity or the reason text. If a hook needs Datadog to show **which hook** blocked and **why**, call this helper. If a "block happened" count is enough, the existing OTEL signal already covers it.

## Why a Client Token (not a full API key)

- Client Tokens are designed by Datadog for client-side use (RUM/Browser SDKs, mobile SDKs). The threat model already assumes the value is reachable by anyone who reads the bundle.
- Worst case if the token leaks: someone spams logs to our tenant. Rotate the token, redeploy, done.
- A full API key would let a leaker write metrics, modify monitors/dashboards, query logs, etc. That blast radius is not appropriate for a value we ship in a Git-tracked plugin.

## Files

| File | Purpose |
|---|---|
| `client-token` | One-line Datadog Client Token. LF-only, no surrounding whitespace. |
| `post.ps1` | Exposes `Send-DatadogHookLog` (Windows). |
| `post.sh` | Exposes `send_datadog_hook_log` (*nix). |

## Helper API

Both helpers share the same parameter set. The caller passes **hook-specific** values; the helper auto-fills the **environment envelope** (host, os, user, pid, parent_pid, session, claude_code.version, terminal, ddsource, ddtags base, event.timestamp).

### PowerShell — `Send-DatadogHookLog`

```powershell
. (Join-Path $PSScriptRoot '..\lib\datadog-log\post.ps1')
Send-DatadogHookLog `
    -Hook        'elevation-guard' `   # required
    -HookEvent   'PreToolUse' `        # required
    -ToolName    $toolName `           # optional — pass '' or 'none' for hooks without an associated tool (SessionStart, Stop, Notification). When set, hook_name = "<HookEvent>:<ToolName>"; otherwise hook_name = "<HookEvent>" and the `tool` field is null.
    -Outcome     'block' `             # required — block | warn | allow | error
    -Reason      'elevated_shell' `    # required — machine-stable code
    -EventName   'hook_block' `        # default 'hook_block'
    -Status      'warning' `           # default 'warning'
    -Message     $human `              # optional human one-liner; auto-composed if omitted
    -StdinJson   $rawStdin `           # optional — helper extracts session_id, transcript_path, cwd, tool_input size
    -Extra       @{ feature_flag='X' } # optional — merged into payload root
```

### Bash — `send_datadog_hook_log`

Bash doesn't have named parameters, so the function reads its inputs from environment variables in a single call:

```bash
. "$(dirname "$0")/../lib/datadog-log/post.sh"

HOOK=elevation-guard \
HOOK_EVENT=PreToolUse \
TOOL_NAME="$tool_name" \
OUTCOME=block \
REASON=elevated_shell \
EVENT_NAME=hook_block \
STATUS=warning \
MESSAGE="$human" \
STDIN_JSON="$payload" \
EXTRA_JSON='{"source":{"tool":"Bash","command":"az login"}}' \
  send_datadog_hook_log
```

Required: `HOOK`, `HOOK_EVENT`, `OUTCOME`, `REASON`. Optional: `TOOL_NAME` (set to `''` or `none` for hooks without an associated tool — SessionStart, Stop, Notification — and the helper drops the `:tool` suffix from `hook_name` and nulls the `tool` field). Defaults: `EVENT_NAME=hook_block`, `STATUS=warning`, `MESSAGE` auto-composed. `EXTRA_JSON` is optional — a JSON object string merged into the top-level body, mirroring the PowerShell helper's `-Extra` hashtable. Invalid JSON is silently ignored.

### `event.name` convention

Callers should set `EventName` / `EVENT_NAME` to **`hook_block`** when the hook denies a tool call (PreToolUse exit 2) and **`hook_warn`** when it logs without blocking. This makes a single Datadog query (`@event.name:hook_block`) cover every blocking hook in the plugin without per-hook disambiguation. The helper default (`hook_block`) is for legacy callers; new code should pass the value explicitly.

## Behaviour

- Reads `client-token` from this directory. If missing or empty → returns silently. **Telemetry is never load-bearing.**
- POSTs to `https://browser-intake-datadoghq.eu/api/v2/logs?dd-api-key=<TOKEN>&ddsource=claude-code-hook&dd-evp-origin=claude-code-hook&dd-evp-origin-version=0.1.0` with `Content-Type: text/plain;charset=UTF-8` and `Origin: https://claude-code-hook.local`. Matches the verified curl test that the browser intake accepts non-browser POSTs as long as a sentinel `Origin` is supplied.
- 2-second timeout. Whole helper wrapped in try/catch (PowerShell) or `2>/dev/null || true` (bash). Network failure, DNS failure, curl missing, JSON malformed — all are swallowed. The hook still exits with whatever code the caller chose.

## Runtime dependencies

| Platform | Required | Optional |
|---|---|---|
| Windows | PowerShell 5.1+ (built-in), `Invoke-WebRequest` | — |
| *nix | `bash`, `curl`, **and one of** `python3` / `jq` for JSON construction | — |

Hand-rolled JSON in shell is fragile (empty values, embedded quotes, multiline strings, unicode), so the bash helper delegates JSON construction to `python3` (preferred) or `jq` (fallback). On standard Ubuntu/macOS dev hosts and WSL, `python3` is part of the base install. On stripped containers (`ubuntu:24.04` Docker base, alpine, debian-slim) neither is present by default — the helper silently no-ops on telemetry while the hook itself still functions normally. Add `python3` (or `jq`) to the container if you need this signal in CI.

## Payload schema

Required fields:

| Field | Source | Example |
|---|---|---|
| `service` | constant | `claude-code` |
| `ddsource` | constant | `claude-code-hook` |
| `event.name` | from `EventName` (default `hook_block`; pass `hook_warn` for non-blocking warns) | `hook_block` |
| `event.timestamp` | helper, ISO-8601 UTC | `2026-04-27T15:13:53.487Z` |
| `hook` | from `Hook` | `elevation-guard` |
| `hook_event` | from `HookEvent` | `PreToolUse` |
| `hook_name` | composed `<HookEvent>:<ToolName>` | `PreToolUse:Read` |
| `tool` | from `ToolName` | `Read` |
| `outcome` | from `Outcome` | `block` |
| `reason` | from `Reason` | `elevated_shell` |
| `status` | from `Status` (default `warning`) | `warning` |
| `os.type` | helper | `windows`/`linux`/`darwin` |
| `user.email` | `~/.claude.json` `oauthAccount.emailAddress` (Claude's authenticated identity); falls back to Windows UPN, then `null` | `rob.taylor@wearefreemarket.com` |

Auto-filled observability fields: `os.version`, `host.name`, `host.arch`, `user.name`, `pid`, `parent_pid`, `session.id`, `transcript_path`, `cwd`, `tool_input_size_bytes`, `claude_code.version`, `terminal.type`, `ddtags`, `message`.

## Datadog queries

```
service:claude-code @ddsource:claude-code-hook                # any hook self-emit
service:claude-code @event.name:hook_block                    # any hook block (any cause)
service:claude-code @event.name:hook_warn                     # any hook warn (any cause)
service:claude-code @hook:bash-command-guard @outcome:block   # specific hook
@source.command:*az*                                          # bash-command-guard: full command field
@session.id:<id>                                              # cross-correlate with OTEL events
```

Saved view columns: `@hook`, `@hook_name`, `@outcome`, `@reason`, `@tool`, `@user.email`, `@os.type`, `@host.name`, `@claude_code.version`, `@session.id`.

## Client Token rotation runbook

1. In Datadog: Organization Settings → API Keys → Client Tokens → revoke the existing `claude-code` token.
2. Generate a new Client Token, name it `claude-code`.
3. Replace the contents of `hooks/lib/datadog-log/client-token` with the new value (single line, LF, no trailing newline).
4. Commit + push + bump plugin version + re-publish so consumers pick up the new token on their next marketplace sync.
5. Old token stops being honoured the moment Datadog processes the revocation.

## Adding a new hook caller

1. Decide a stable `Hook` identifier (the script name without extension is fine).
2. Pick `Outcome` and `Reason` codes — keep `Reason` machine-stable (snake_case, no spaces) so it can drive monitors. Put any human prose in `Message`.
3. Source/dot-source this helper and call.
4. Test with `client-token` removed (no-op) and present (log indexes within ~30s).
