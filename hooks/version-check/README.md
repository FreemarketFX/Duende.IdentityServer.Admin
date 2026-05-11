# version-check

A `SessionStart` hook that warns the user when their installed copy of `freemarket-claude-skills` is behind the version on `main`. The warning is delivered as `additionalContext` on the SessionStart payload, so Claude sees it as part of the session prompt and can mention the upgrade path naturally.

## How it works

`hooks.json` invokes a single file: `version-check.cmd`. This file is the same **sh + cmd polyglot** pattern used by `elevation-guard`. No `node`, no `pwsh`, no extra runtime — just the shells that ship with the OS, plus the [GitHub CLI](https://cli.github.com/) (`gh`):

| OS | Dispatcher runs | Detection script | Network |
|---|---|---|---|
| Windows | `cmd.exe` (built-in) | `version-check.ps1` (Windows PowerShell 5.1, built-in) | `gh api` |
| Linux / macOS | `/bin/sh` runs the polyglot, `exec`s `bash` | `version-check.sh` | `gh api` |

### Flow

1. **Read installed version** — `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/marketplace.json` `metadata.version`. We compare against the marketplace metadata version because that's the field the marketplace itself consumes; per [`CLAUDE.md`](../../CLAUDE.md), `plugin.json`'s `version` is kept in lockstep, but the marketplace value is the load-bearing one.
2. **Cache check** — `${TEMP|TMPDIR}/freemarket-claude-skills-version-check.json`. Three internal cached states drive the hot path:
   - `ok` (1h TTL) → reuse `latest_version`, fall through to compare
   - `gh_missing` (1h TTL) → emit "install gh" warning, log, exit
   - `gh_fetch_failed` (15min TTL) → log only, silent exit, no fresh network call
3. **Check `gh` is on PATH** — if missing, write `gh_missing` cache + emit `additionalContext` warning ("install GitHub CLI to enable plugin update checks") + log to Datadog. The user is warned but the hook still exits 0; they're prompted at most once per hour.
4. **Fetch upstream** — `gh api repos/FreemarketFX/claude-shared/contents/.claude-plugin/marketplace.json -H "Accept: application/vnd.github.raw"`. 3-second wall-clock timeout. Reuses whatever auth token the user already has from `gh auth login` — works for our private source repo, no extra setup.
5. **Compare** — if `installed < latest`, emit a SessionStart `additionalContext` JSON document to stdout:
   ```json
   {"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"Tell the user at the start of your next response that the freemarket-claude-skills plugin is outdated (installed 1.21.0, latest 1.22.0) and they should run `/plugin update freemarket-claude-skills` to upgrade."}}
   ```
   The wording is deliberately imperative — `additionalContext` is injected into Claude's context but isn't a UI banner; if it were phrased declaratively Claude wouldn't proactively surface it on focused user questions. See [`CLAUDE.md`](CLAUDE.md) "Why imperative wording" for the live test that established this.

### Telemetry contract

Every code path emits exactly one Datadog log via the shared helper at [`../lib/datadog-log/`](../lib/datadog-log/README.md). The fields are tightly constrained:

| Field | Value |
|---|---|
| `event.name` | `freemarket_tools_version_check` (always) |
| `outcome` | `ok` \| `warn` \| `error` |
| `status` | `info` (when outcome=ok) \| `warn` (when outcome=warn) \| `error` (when outcome=error) |
| `reason` | `fresh_check` \| `cache_hit` \| `gh_missing` \| `gh_fetch_failed` \| `invalid_version` \| `marketplace_json_missing` |
| `installed_version` | present whenever the script successfully read it (i.e. on every path except `marketplace_json_missing`) |
| `latest_version` | present whenever the script successfully read or recalled it (any `ok`/`warn`, plus `invalid_version` when upstream side fired) |
| `tool` | `null` (SessionStart hooks have no associated tool) |
| `hook_name` | `SessionStart` (no `:tool` suffix) |

Outcome × reason matrix:

| Path | outcome | reason |
|---|---|---|
| Up-to-date, fresh fetch | `ok` | `fresh_check` |
| Up-to-date, cache hit | `ok` | `cache_hit` |
| Outdated, fresh fetch | `warn` | `fresh_check` |
| Outdated, cache hit | `warn` | `cache_hit` |
| `gh` not on PATH | `error` | `gh_missing` |
| `gh api` failed (timeout / auth / empty / parse) | `error` | `gh_fetch_failed` |
| Installed marketplace.json missing or unparseable | `error` | `marketplace_json_missing` |
| Either side's version isn't valid semver | `error` | `invalid_version` |

### Fail-open contract

The hook **always exits 0**. There is no "deny" path — SessionStart hooks cannot block startup. Unexpected errors are swallowed and reported to Datadog with `outcome=error`.

The two cache TTLs are deliberate:
- `gh_missing` (1h) — the user-facing warning is helpful but shouldn't fire on every single session start. Once an hour is enough to remind without being noisy.
- `gh_fetch_failed` (15min) — in sandboxed envs blocking egress to `api.github.com`, or when `gh auth` is broken, we don't want to pay a 3-second timeout on every session start. The shorter TTL gives faster recovery once the env is fixed.

## Querying logs

**Datadog:**

```
service:claude-code @event.name:freemarket_tools_version_check                              # all events
service:claude-code @event.name:freemarket_tools_version_check @outcome:warn                # users on outdated installs
service:claude-code @event.name:freemarket_tools_version_check @outcome:error @reason:gh_missing       # users without gh installed
service:claude-code @event.name:freemarket_tools_version_check @outcome:error @reason:gh_fetch_failed  # users with gh but auth/network broken
```

Saved view columns: `@hook`, `@outcome`, `@reason`, `@installed_version`, `@latest_version`, `@user.email`, `@host.name`, `@session.id`, `@claude_code.version`. Both `installed_version` and `latest_version` are emitted on every path that successfully reads them (PowerShell via `-Extra`; bash via `EXTRA_JSON`).

## Cache file shape

The on-disk cache uses an internal `outcome` field that is **not** the same vocabulary as the Datadog log — see the implementation notes in [`CLAUDE.md`](CLAUDE.md). Three states:

```jsonc
// Up-to-date / outdated determined at compare time
{ "checked_at": "2026-04-28T14:32:11Z", "outcome": "ok", "latest_version": "1.22.0" }

// gh not installed (1h TTL — re-prompts user every hour)
{ "checked_at": "2026-04-28T14:32:11Z", "outcome": "gh_missing" }

// gh present but transient failure (15min TTL — silent)
{ "checked_at": "2026-04-28T14:32:11Z", "outcome": "gh_fetch_failed" }
```

Corrupt / unparseable cache is treated as a miss and silently overwritten.

## Authentication

The hook uses **whatever auth token `gh auth login` configured**. That means:

- `gh auth login --hostname github.com` against the user's normal GitHub account → works (same access the user has via the website).
- Repo-scoped fine-grained PAT installed via `gh auth login --with-token` → works.
- `gh` installed but never authenticated → `gh api` returns non-zero → `outcome=error reason=gh_fetch_failed`. Hook exits 0 silently; misconfiguration is observable in Datadog.
- `gh` not installed at all → `outcome=error reason=gh_missing`, user sees the install prompt once per hour.

The hook does **not** prompt for credentials, does **not** read `.netrc`, does **not** fall back to a public raw URL (the source repo is private — the URL would 404 forever). If `gh api repos/FreemarketFX/claude-shared/contents/.claude-plugin/marketplace.json` works on the user's machine, the hook works.

## Standalone testing

```powershell
# Windows — current install up-to-date → exit 0, no stdout.
$env:CLAUDE_PLUGIN_ROOT = (Resolve-Path .).Path
powershell.exe -NoProfile -File hooks/version-check/version-check.ps1

# Force the outdated path by editing .claude-plugin/marketplace.json
# metadata.version → 0.1.0, then re-run. Expect the additionalContext
# JSON on stdout.

# Force the gh-missing path: prepend a directory to PATH that hides gh, blow
# away the cache, re-run. Expect the install-gh warning on stdout.
Remove-Item $env:TEMP\freemarket-claude-skills-version-check.json -ErrorAction SilentlyContinue
$savedPath = $env:PATH; $env:PATH = "C:\nonexistent"; powershell.exe -NoProfile -File hooks/version-check/version-check.ps1; $env:PATH = $savedPath
```

```bash
# *nix — same shape.
CLAUDE_PLUGIN_ROOT="$PWD" bash hooks/version-check/version-check.sh

# Outdated: edit marketplace.json metadata.version → 0.1.0, rerun, expect stdout JSON.
# gh-missing: rm $TMPDIR/freemarket-claude-skills-version-check.json; PATH=/nonexistent bash hooks/version-check/version-check.sh
```

A scripted harness for each platform lives at [`test-version-check.ps1`](./test-version-check.ps1) and [`test-version-check.sh`](./test-version-check.sh) — both mock the cache file and exercise every code path (up-to-date, outdated, gh_missing, gh_fetch_failed, missing marketplace.json, invalid version) without touching the real network.

## Line endings

`version-check.cmd` MUST be checked in with LF line endings — POSIX `sh` requires clean LF for the heredoc to terminate correctly on `::CMDLITERAL`. Pinned in `.gitattributes`.

## Disabling

Remove the `SessionStart` block from `hooks/hooks.json`, or uninstall the plugin. There is no per-session escape hatch — but the hook never blocks anything, so there's nothing to escape from.
