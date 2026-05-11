# elevation-guard

A `PreToolUse` hook that **denies every tool call** when Claude Code is running with elevated OS privileges (Windows Administrator / Unix root). The block is observable from OTEL logs via a stable sentinel string.

## How it works

`hooks.json` invokes a single file: `elevation-guard.cmd`. This file is a **sh + cmd polyglot** — the same bytes are valid in both Windows `cmd.exe` and POSIX `sh`. No `node`, no `pwsh`, no extra runtime — just the shells that ship with the OS:

| OS | Dispatcher runs | Detection script | Detection method |
|---|---|---|---|
| Windows | `cmd.exe` (built-in, recognises `.cmd` via PATHEXT) | `elevation-guard.ps1` (Windows PowerShell 5.1, built-in) | `WindowsPrincipal.IsInRole(Administrator)` |
| Linux / macOS | `/bin/sh` runs the file as a shell script, then `exec`s `bash` | `elevation-guard.sh` | `id -u -eq 0` |

The polyglot's structure:

```
:<<"::CMDLITERAL"                 <- sh sees a heredoc; cmd sees a (silent) label
@echo off                         <- cmd code (skipped by sh inside heredoc)
powershell.exe ...                <- cmd code
exit /b %ERRORLEVEL%              <- cmd code
::CMDLITERAL                      <- end of sh heredoc
exec bash "$(dirname "$0")/elevation-guard.sh"   <- sh code (cmd never reaches it)
```

There is intentionally **no `#!/usr/bin/env bash` shebang** on line 1: cmd.exe cannot parse `#` and would echo `'#!' is not recognized…` to stderr before reaching `@echo off`, which would surface in the user's transcript. On *nix, the absence of a kernel-honored shebang is fine — `hooks.json` invokes the file via `/bin/sh`, which runs it as a shell script, consumes the heredoc, and reaches the `exec bash …elevation-guard.sh` trampoline.

When elevation is detected, both detection scripts write **two lines** to stderr and `exit 2`:

```
Blocked: Claude Code is running in an elevated/Administrator shell (<USER>). Restart Claude Code from a non-elevated shell to proceed.
CLAUDE_ELEVATION_BLOCK tool=<TOOL> user=<USER> os=<OS> pid=<PID>
```

The first line is human-readable so Claude can relay the actual reason to the user. The second line is the stable, greppable OTEL sentinel — unchanged from before, so existing log filters keep working.

Per the Claude Code hook contract, exit 2 from `PreToolUse` denies the tool call and feeds stderr back to Claude — and into the OTEL hook telemetry / debug log.

When *not* elevated, the script exits 0 silently.

All scripts fail **open** on unexpected errors (missing interpreter, parse failures, etc.) so a broken hook can never wedge Claude.

When a block fires, the detector additionally calls `Send-DatadogHookLog` / `send_datadog_hook_log` from [`../lib/datadog-log/`](../lib/datadog-log/README.md), which POSTs a structured log to Datadog's browser-intake endpoint authenticated by a bundled Client Token. Failure of that side-channel (missing token, network down, etc.) does **not** affect the block path.

## Querying logs

**Datadog (preferred — carries hook name and reason):**

```
service:claude-code @hook:elevation-guard @outcome:block
```

Saved view columns: `@hook_name`, `@reason`, `@user.email`, `@host.name`, `@os.type`, `@session.id`, `@claude_code.version`. See [`../lib/datadog-log/README.md`](../lib/datadog-log/README.md) for the full payload schema.

**OTEL stderr sentinel (legacy / debug-log fallback):**

```
message =~ /^CLAUDE_ELEVATION_BLOCK /
```

Space-separated `key=value` pairs after the prefix can be parsed by any structured-log tool.

## Standalone testing

```powershell
# Windows: as a normal user → exit 0
powershell.exe -NoProfile -File hooks/elevation-guard/elevation-guard.ps1
# From an Administrator shell → exit 2 + human line + sentinel on stderr
# (and a Datadog log if hooks/lib/datadog-log/client-token is present)
```

```bash
# *nix: as normal user → exit 0
bash hooks/elevation-guard/elevation-guard.sh
# As root → exit 2 + human line + sentinel on stderr
# (and a Datadog log if hooks/lib/datadog-log/client-token is present
#  and python3 or jq is available)
sudo bash hooks/elevation-guard/elevation-guard.sh
```

## Line endings

`elevation-guard.cmd` MUST be checked in with LF line endings — POSIX `sh` requires clean LF for the heredoc to terminate correctly on `::CMDLITERAL`. The repo's `.gitattributes` pins this. If you edit the file in an editor that auto-converts to CRLF, the *nix branch of the polyglot will break.

## Disabling

Remove the `PreToolUse` block from `hooks/hooks.json`, or uninstall the plugin. There is intentionally **no per-call escape hatch**.
