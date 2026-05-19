# version-check — implementation notes

Notes for editors of this hook. End-user usage and telemetry queries live in [`README.md`](README.md).

## Telemetry contract (don't break this)

The hook emits exactly one Datadog log per run with a tightly constrained shape:

| Field | Allowed values |
|---|---|
| `event.name` | `freemarket_tools_version_check` (always) |
| `outcome` | `ok` \| `warn` \| `error` |
| `status` | `info` (outcome=ok) \| `warn` (outcome=warn) \| `error` (outcome=error) |
| `reason` | `fresh_check` \| `cache_hit` \| `gh_missing` \| `gh_fetch_failed` \| `invalid_version` \| `marketplace_json_missing` |
| `installed_version` / `latest_version` | populated whenever known, via `-Extra` (PowerShell) / `EXTRA_JSON` (bash) |

Any new code path must pick from this enum. If you find yourself wanting a 7th reason, first ask whether one of the existing ones already covers it semantically. Splitting the reason space increases dashboard surface area and dilutes alert signal.

`outcome=warn` (i.e. the user is on an outdated install) is **the** load-bearing signal that drives the user-facing prompt. Don't downgrade it to info under any "let me batch this" instinct.

## Two outcome vocabularies (cache vs log) — don't mix them

The on-disk cache file uses an internal `outcome` field with values `ok | gh_missing | gh_fetch_failed`. These drive the next session's hot-path routing (which TTL applies, what to show the user). They are **not the same** as the Datadog log `outcome` (`ok | warn | error`). The mapping is done at log time:

| cache.outcome | Log outcome | Log reason |
|---|---|---|
| `ok` + installed ≥ latest | `ok` | `cache_hit` (or `fresh_check` if just fetched) |
| `ok` + installed < latest | `warn` | `cache_hit` (or `fresh_check`) |
| `gh_missing` | `error` | `gh_missing` |
| `gh_fetch_failed` | `error` | `gh_fetch_failed` |

If you find yourself wanting to add a fourth cache state, first check whether you can fold it into one of the existing three.

## Why marketplace.json, not plugin.json

We compare against `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/marketplace.json` `metadata.version` rather than `plugin.json` `version`. The marketplace metadata is the field the marketplace machinery actually consumes when resolving plugin versions; `plugin.json` is kept in lockstep by convention (top-level `CLAUDE.md` rule) but the marketplace value is load-bearing. If they ever drift, the marketplace value wins, so it's the version that needs to be checked. Both fetches (installed and upstream) target the same field.

## Hot-path discipline

This hook fires on **every** SessionStart. The cache check is the hot path and must avoid network I/O on a cache hit. Order of operations in both scripts:

1. Read installed version (cheap local file read).
2. Read cache file. Three cached states branch the hot path:
   - `ok` (age < 1h) → use cached `latest_version`, fall through to compare. **Never call the network.**
   - `gh_missing` (age < 1h) → emit the install-gh `additionalContext` warning, log Datadog (outcome=error reason=gh_missing), `exit 0`. **Never call the network.**
   - `gh_fetch_failed` (age < 15min) → log Datadog (outcome=error reason=gh_fetch_failed), `exit 0`. **Never call the network.** No stdout — transient errors don't warn the user.
3. Only fall through to `gh api` when the cache is missing or stale.

Don't re-order this — the cache fast-paths are what keep this hook from paying a 3-second `gh api` timeout on every single session start in misconfigured environments.

## Two stdout-emitting paths

The hook has two distinct user-facing warnings:

1. **Outdated install** (outcome=warn): `"Tell the user at the start of your next response that the $plugin plugin is outdated (installed X, latest Y) and they should run \`/plugin update $plugin\` to upgrade."`
2. **gh missing** (outcome=error reason=gh_missing): `"Tell the user at the start of your next response that the $plugin plugin's version-check hook can't run because GitHub CLI (gh) isn't installed. Direct them to install it from https://cli.github.com/ and then run \`gh auth login\` so plugin update prompts can work."`

Both go through the same `additionalContext` JSON shape. Both respect a 1h TTL — when the cached state is `gh_missing`, we re-emit the warning every cache hit, but only after writing the cache fresh once an hour. `gh_fetch_failed` deliberately does **not** emit stdout — auth/network blips shouldn't be in the user's face; they're for ops to find via Datadog.

### Why imperative wording (and don't change it back)

`additionalContext` is **not a UI banner** — Claude Code injects it into the model's context but the user sees nothing directly. Whether the user actually gets warned depends entirely on whether Claude proactively surfaces the context in its first response. Verified live: passive informational wording ("freemarket-claude-skills is outdated") sat in context but Claude only volunteered it when the user asked an open-ended question ("what should I know"); on focused questions ("hi", "fix this bug") the warning was silently dropped while Claude answered the actual question.

Imperative second-person wording directed at Claude ("Tell the user at the start of your next response that…") makes Claude treat the additionalContext as an instruction, not a fact, and reliably surface it on the first turn regardless of what the user asked. This is the same pattern used in system prompts to force proactive behaviour.

Don't switch back to declarative wording unless you've found a different forcing function — silent context that the user never sees defeats the entire point of the hook.

## Fail-open contract

Every error path exits 0. SessionStart hooks cannot deny a session, but a hook that prints garbage to stdout will still confuse Claude. Specifically:

- Installed marketplace.json missing or unparseable → `outcome=error reason=marketplace_json_missing` + `exit 0` with no stdout.
- Either side's version is not semver → `outcome=error reason=invalid_version` + `exit 0` with no stdout.
- `gh` not on PATH → `outcome=error reason=gh_missing` + write 1h cache + emit install-gh stdout + `exit 0`.
- `gh api` failure / timeout / empty / malformed JSON → `outcome=error reason=gh_fetch_failed` + write 15min negative cache + `exit 0` with no stdout.
- `Send-DatadogHookLog` failures are swallowed inside the helper itself.

Stdout is only ever the `additionalContext` JSON, on either the outdated-install path or the gh_missing path. Anything else and Claude will treat it as a hook output error.

## Semver

Validation: `^\d+\.\d+\.\d+$`. No pre-release suffixes (`-rc.1`), no build metadata (`+sha`). The plugin doesn't ship them; if we ever do, extend `Test-SemVer` / `is_semver` and `Compare-SemVer` / `cmp_semver` together — they are intentionally co-located in each script.

`Compare-SemVer` returns `-1 / 0 / 1`. `cmp_semver` (bash) returns `1 / 0 / 2` because shells can't return negative ints — both call sites translate the result accordingly. Don't be tempted to "normalise" them; the asymmetry is forced by `bash`. Bash also forces base-10 evaluation in `cmp_semver` via `10#$x` to avoid octal interpretation of leading-zero version components.

In the bash side, the call site uses `cmp=0; cmp_semver "$a" "$b" || cmp=$?` rather than a bare invocation — `trap 'exit 0' ERR` would otherwise fire on the `cmp_semver` non-zero return (its API) and silently swallow the warn-output branch. The `|| ...` makes it a compound command, which suppresses the trap.

## Telemetry payload extras

Both helpers now accept extras: PowerShell via `-Extra @{ installed_version = ...; latest_version = ... }`, bash via `EXTRA_JSON='{"installed_version":"...","latest_version":"..."}'`. The version-check `send_telemetry` function in each script builds these from positional args (`installed_arg` / `latest_arg`) so every Datadog log carries both versions whenever the script knew them — including cache-hit paths where a previous run wrote the cache and a later session reads it back.

The bash `send_telemetry` builds `EXTRA_JSON` via python3 with a jq fallback, mirroring the existing JSON-construction strategy in `lib/datadog-log/post.sh`. If neither is on PATH, extras are silently dropped and the rest of the log still goes through.

## Cache file location

- Windows: `%TEMP%\freemarket-claude-skills-version-check.json`
- *nix: `${TMPDIR:-/tmp}/freemarket-claude-skills-version-check.json`

Per-machine, ephemeral, no directory creation needed. Don't move it into `${CLAUDE_PLUGIN_ROOT}` — that path is on the plugin install root and may be read-only on some installs.

## Windows PowerShell stdout encoding

`Write-AdditionalContext` (PowerShell side) **must** write the JSON via `[Console]::OpenStandardOutput()` with a no-BOM UTF-8 encoder, **not** via `Write-Output | ConvertTo-Json`. Reason:

Windows PowerShell 5.1 encodes redirected stdout as **UTF-16 LE with a BOM** by default. When Claude Code launches the hook via the cmd dispatcher and reads stdout as UTF-8, it sees the `0xFF 0xFE` BOM followed by interleaved null bytes between every ASCII character. The JSON parse fails silently — the hook still runs to completion and emits its Datadog log (which is exactly the symptom we hit in production: warn outcomes visible in Datadog, no upgrade prompt visible to the user).

The fix bypasses PowerShell's output formatter entirely:

```powershell
$json = $output | ConvertTo-Json -Depth 5 -Compress
$bytes = [Text.UTF8Encoding]::new($false).GetBytes($json)
$stdout = [Console]::OpenStandardOutput()
$stdout.Write($bytes, 0, $bytes.Length)
$stdout.Flush()
```

No BOM, no PowerShell preamble, no trailing newline. Don't refactor this back to `Write-Output` or `Write-Host` — both go through the formatter and re-encode.

**Diagnostic gotcha**: capturing stdout via the obvious `& powershell.exe -File ... > out.bin` from another PowerShell session will MISLEAD you, because the outer PowerShell `>` redirection re-encodes the captured bytes as UTF-16 LE with BOM regardless of what the inner script emitted. To verify the hook output end-to-end, invoke via cmd.exe instead:

```powershell
Start-Process -NoNewWindow -Wait -FilePath cmd.exe `
  -ArgumentList '/c',"hooks\version-check\version-check.cmd > out.bin"
[IO.File]::ReadAllBytes('out.bin')[0..7] | ForEach-Object { '{0:X2}' -f $_ }
# expect: 7B 22 68 ... (i.e. {"h...) NOT FF FE 7B 00
```

The bash side is not affected — `printf` writes raw bytes verbatim.

## Polyglot dispatcher

`version-check.cmd` is byte-identical in structure to `elevation-guard.cmd`. If you change the dispatcher, update `.gitattributes` to pin LF endings (already done) and run `git ls-files --eol hooks/version-check/version-check.cmd` to confirm `i/lf  w/lf  attr/text=auto eol=lf`.

## Why not check `~/.claude/plugins/cache/...` directly

Earlier drafts read `~/.claude/plugins/cache/{plugin-id}/plugin.json` to find the install. This is fragile — the slug depends on the marketplace name (`freemarket-tools`) and the plugin name (`freemarket-claude-skills`), and the layout has changed across Claude Code versions. `${CLAUDE_PLUGIN_ROOT}` is the documented contract: Claude sets it to the install root every time the hook runs. Use it.

## Why `gh api` instead of raw URL or `git fetch`

Three approaches were tried in order before landing on `gh api`. The history is preserved here so future editors don't repeat them:

1. **Public raw URL** (`https://raw.githubusercontent.com/.../plugin.json`). Works for public repos. `claude-shared` is private → HTTP 404 for every consumer → every install would have shown `fetch_failed` forever, never warning anyone.
2. **`git fetch` against `${CLAUDE_PLUGIN_ROOT}`.** The premise was "if the marketplace cloned this install, `git fetch origin main` should also work." False premise: the Claude Code marketplace **extracts a versioned snapshot** to `~/.claude/plugins/cache/{marketplace}/{plugin}/{version}/`, it does **not** leave a usable `.git` dir. `git rev-parse --is-inside-work-tree` returns false → every install hits `not_git_repo` → no warnings.
3. **`gh api repos/.../contents/.claude-plugin/marketplace.json`.** Reuses the user's existing `gh auth login` token. Works for private repos, doesn't require the install to be a git work tree, and most Freemarket devs already have `gh` configured for PR work. The trade-off is the runtime dependency on `gh`, which we surface as a one-warning-per-hour `additionalContext` prompt rather than silently failing.

If you ever need to remove the `gh` dependency, the only viable replacement is making the source repo public — at which point the raw-URL approach becomes the simplest.
