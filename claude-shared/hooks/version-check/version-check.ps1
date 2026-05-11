<#
.SYNOPSIS
    SessionStart plugin-version-check hook (Windows).

.DESCRIPTION
    On every Claude Code session start, compares the installed plugin version
    (read from ${CLAUDE_PLUGIN_ROOT}/.claude-plugin/marketplace.json
    metadata.version) against the same field on `main` upstream. Fetch goes
    through the GitHub CLI (`gh api`), reusing whatever auth token the user
    already has from `gh auth login` — works for our private source repo, no
    extra setup. When the install is behind, emits a SessionStart
    additionalContext JSON document to stdout so Claude can prompt the user
    to run /plugin update.

    If `gh` is not on PATH the hook emits a one-time-per-hour
    additionalContext warning advising the user to install it. All other
    error paths exit 0 silently. Compatible with Windows PowerShell 5.1
    (built into Windows) — does NOT require pwsh.

    Telemetry contract:
      outcome ∈ { ok, warn, error }
      status  matches outcome (ok→info, warn→warn, error→error)
      reason  ∈ { fresh_check, cache_hit, gh_missing, gh_fetch_failed,
                  invalid_version, marketplace_json_missing }
      installed_version / latest_version are present whenever the script
      successfully read them, irrespective of outcome.
#>

trap { exit 0 }

$pluginName    = 'freemarket-claude-skills'
$repoOwner     = 'FreemarketFX'
$repoName      = 'claude-shared'
$cacheTtlOk    = 3600   # 1h — also used for gh_missing
$cacheTtlFail  = 900    # 15min — gh_fetch_failed
$cachePath     = Join-Path $env:TEMP "$pluginName-version-check.json"
$fetchTimeoutMs = 3000

# SessionStart additionalContext is injected into Claude's session context but
# Claude won't surface it to the user unless prompted to. Phrase as an
# imperative instruction directed at Claude so the warning actually reaches
# the user on their first turn -- and instruct Claude to use a markdown
# blockquote + emoji + bold so the warning is visually distinct from the
# rest of the response and can't be missed as a stray bullet point.
#
# Note: Windows PowerShell 5.1 reads .ps1 source as CP1252 unless there's a
# BOM, which mangles literal UTF-8 multibyte chars (em-dash, emoji) into
# byte sequences that include `"` and prematurely terminate the string.
# We compose the unicode chars at runtime via [char] so the source stays
# strict-ASCII and the file can be saved without a BOM.
$warningEmoji = [char]0x26A0 + [string][char]0xFE0F  # ⚠️
$emDash = [string][char]0x2014  # —
$ghMissingMessage = "Display this prominently at the very top of your next response, as a markdown blockquote on its own line, prefixed with the warning emoji and using **bold** for the key phrase. Do not paraphrase, but include all of the information given here. Do not summarise it under another heading. Exact format:`n`n> $warningEmoji **${pluginName} plugin update-check disabled** $emDash install the GitHub CLI (``gh``) and run ``gh auth login`` so plugin update prompts can work. See https://cli.github.com/."

# Read SessionStart stdin payload (best-effort) so the Datadog log can carry
# session_id / cwd / source. Never block on a non-redirected stdin.
$rawStdin = $null
if ([Console]::IsInputRedirected) {
    try { $rawStdin = [Console]::In.ReadToEnd() } catch { }
}

# Source the Datadog helper once at script load rather than dot-sourcing on
# every Send-Telemetry call. If post.ps1 is missing, Send-DatadogHookLog
# won't be defined; Send-Telemetry catches the resulting "command not found"
# — telemetry is best-effort, never load-bearing.
try { . (Join-Path $PSScriptRoot '..\lib\datadog-log\post.ps1') } catch { }

# Single telemetry sink. Outcome ∈ { ok | warn | error } maps 1-1 to
# Datadog log status (ok→info, warn→warn, error→error). installed_version
# and latest_version flow through as Extras whenever they're known.
function Send-Telemetry {
    param(
        [Parameter(Mandatory)] [ValidateSet('ok','warn','error')] [string]$Outcome,
        [Parameter(Mandatory)] [string]$Reason,
        [string]$Message,
        [string]$Installed,
        [string]$Latest
    )
    try {
        $extra = @{}
        if ($Installed) { $extra['installed_version'] = $Installed }
        if ($Latest)    { $extra['latest_version']    = $Latest }
        $status = switch ($Outcome) { 'ok' { 'info' } 'warn' { 'warn' } default { 'error' } }
        Send-DatadogHookLog `
            -Hook 'version-check' `
            -HookEvent 'SessionStart' `
            -Outcome $Outcome `
            -Reason $Reason `
            -EventName 'freemarket_tools_version_check' `
            -Status $status `
            -Message $Message `
            -StdinJson $rawStdin `
            -Extra $extra
    } catch { }
}

function Write-AdditionalContext {
    param([string]$Message)
    $output = [ordered]@{
        hookSpecificOutput = [ordered]@{
            hookEventName     = 'SessionStart'
            additionalContext = $Message
        }
    }
    $json = $output | ConvertTo-Json -Depth 5 -Compress
    # Bypass PowerShell's output formatter and write raw UTF-8 bytes to
    # stdout. Windows PowerShell 5.1 encodes redirected stdout as UTF-16 LE
    # with a BOM by default — Claude Code reads stdout as UTF-8, sees the
    # BOM + interleaved null bytes, fails to parse the JSON, and silently
    # drops the additionalContext. No BOM, no preamble, no trailing newline.
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($json)
    $stdout = [Console]::OpenStandardOutput()
    $stdout.Write($bytes, 0, $bytes.Length)
    $stdout.Flush()
}

function Test-SemVer {
    param([string]$V)
    return ($V -and $V -match '^\d+\.\d+\.\d+$')
}

function Compare-SemVer {
    param([string]$A, [string]$B)
    # Returns -1 if A<B, 0 if equal, 1 if A>B. Assumes both already pass Test-SemVer.
    $aParts = $A.Split('.') | ForEach-Object { [int]$_ }
    $bParts = $B.Split('.') | ForEach-Object { [int]$_ }
    for ($i = 0; $i -lt 3; $i++) {
        if ($aParts[$i] -lt $bParts[$i]) { return -1 }
        if ($aParts[$i] -gt $bParts[$i]) { return  1 }
    }
    return 0
}

# Cache file uses an internal `outcome` field with three values that drive
# the next session's hot path. NOT the same vocabulary as the Datadog
# `outcome` — we map at log time:
#   cache.outcome=ok            (1h TTL) → log outcome=ok|warn (depends on compare)
#   cache.outcome=gh_missing    (1h TTL) → log outcome=error reason=gh_missing
#   cache.outcome=gh_fetch_failed (15min TTL) → log outcome=error reason=gh_fetch_failed
#
# Timestamp format matches the bash side's `date -u +%Y-%m-%dT%H:%M:%SZ` so
# a cross-platform reader (e.g. macOS reading a Windows-written cache via a
# shared $TEMP) parses cleanly. Don't switch to .ToString('o') — that adds
# millisecond precision that BSD `date -ju -f` won't parse.
#
# Bytes are written via a no-BOM UTF-8 encoder rather than `Set-Content
# -Encoding UTF8`. Windows PowerShell 5.1's "UTF8" actually means
# "UTF-8 with BOM"; the bash sed-fallback JSON parser would silently fail
# on the BOM-prefixed first key, and python3 json.loads rejects leading
# BOM outright. Same class of bug as the additionalContext output fix.
function Write-Cache {
    param([string]$CacheOutcome, [string]$LatestVersion)
    try {
        $checkedAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        $obj = if ($CacheOutcome -eq 'ok') {
            [ordered]@{ checked_at = $checkedAt; outcome = 'ok'; latest_version = $LatestVersion }
        } else {
            [ordered]@{ checked_at = $checkedAt; outcome = $CacheOutcome }
        }
        $bytes = [Text.UTF8Encoding]::new($false).GetBytes(($obj | ConvertTo-Json -Compress))
        [IO.File]::WriteAllBytes($cachePath, $bytes)
    } catch { }
}

# Run an external process with a wall-clock timeout. Returns
# @{ ok=$bool; out=string }. Built for Windows PowerShell 5.1 — uses
# .Arguments (string), not the PowerShell-7-only .ArgumentList collection.
# Each arg is wrapped in double quotes and embedded quotes are escaped;
# arg values are paths / refs / API URLs, no shell metacharacters.
function Invoke-Process {
    param([string]$FileName, [string[]]$ProcessArgs, [int]$TimeoutMs = $fetchTimeoutMs)
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $FileName
    $quoted = foreach ($a in $ProcessArgs) { '"' + ($a -replace '"', '\"') + '"' }
    $psi.Arguments = ($quoted -join ' ')
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow  = $true
    $proc = [Diagnostics.Process]::Start($psi)
    # Drain stdout AND stderr async to prevent pipe-buffer deadlock. Windows
    # pipe buffer is ~64KB; if gh writes a verbose error to stderr (e.g. auth
    # failure with stack trace), filling the buffer would block gh waiting on
    # the write while we wait on WaitForExit, costing the full timeout budget
    # on a fast-failing call.
    $stdout = $proc.StandardOutput.ReadToEndAsync()
    $stderr = $proc.StandardError.ReadToEndAsync()
    if (-not $proc.WaitForExit($TimeoutMs)) {
        try { $proc.Kill() } catch { }
        return @{ ok = $false; out = '' }
    }
    [Threading.Tasks.Task]::WaitAll(@($stdout, $stderr))
    return @{ ok = ($proc.ExitCode -eq 0); out = $stdout.Result }
}

# Resolve plugin root. CLAUDE_PLUGIN_ROOT is set by Claude Code when invoking
# hooks; fall back to two levels up from this script for standalone testing.
# Trim a trailing separator so callers that build paths via string-concat
# don't end up with double-separators or escaped-quote oddities.
$pluginRoot = $env:CLAUDE_PLUGIN_ROOT
if (-not $pluginRoot) { $pluginRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
$pluginRoot = $pluginRoot.TrimEnd('\','/')

$installedPath = Join-Path $pluginRoot '.claude-plugin\marketplace.json'
if (-not (Test-Path -LiteralPath $installedPath)) {
    Send-Telemetry -Outcome 'error' -Reason 'marketplace_json_missing' -Message "marketplace.json not found at $installedPath"
    exit 0
}

try {
    $installedJson = Get-Content -LiteralPath $installedPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    $installed = [string]$installedJson.metadata.version
} catch {
    Send-Telemetry -Outcome 'error' -Reason 'marketplace_json_missing' -Message 'marketplace.json present but unparseable'
    exit 0
}

if (-not (Test-SemVer $installed)) {
    # Don't echo the unparseable string back as installed_version — only
    # valid semver values flow into the version extras, so dashboards stay
    # clean and the field type stays stable.
    Send-Telemetry -Outcome 'error' -Reason 'invalid_version' -Message 'installed metadata.version is not semver'
    exit 0
}

# Cache lookup. Cache hit avoids the network call entirely; this is the hot
# path for the hook because SessionStart fires on every session start.
$latest = $null
$fromCache = $false
if (Test-Path -LiteralPath $cachePath) {
    try {
        $cache = Get-Content -LiteralPath $cachePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        $age = ((Get-Date).ToUniversalTime() - [DateTime]::Parse($cache.checked_at).ToUniversalTime()).TotalSeconds
        $ttl = if ($cache.outcome -eq 'gh_fetch_failed') { $cacheTtlFail } else { $cacheTtlOk }
        if ($age -ge 0 -and $age -lt $ttl) {
            switch ($cache.outcome) {
                'ok' {
                    if (Test-SemVer $cache.latest_version) {
                        $latest = [string]$cache.latest_version
                        $fromCache = $true
                    }
                }
                'gh_missing' {
                    Write-AdditionalContext $ghMissingMessage
                    Send-Telemetry -Outcome 'error' -Reason 'gh_missing' -Message $ghMissingMessage -Installed $installed
                    exit 0
                }
                'gh_fetch_failed' {
                    # Honour negative cache: skip network, log the cached error
                    # state so misconfigured clients are still tracked even on
                    # cache hits. No stdout — transient errors don't warn the user.
                    Send-Telemetry -Outcome 'error' -Reason 'gh_fetch_failed' -Installed $installed
                    exit 0
                }
            }
        }
    } catch {
        # Corrupt cache — treat as miss.
    }
}

if (-not $latest) {
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        # gh missing is a stable user-facing condition. Cache for the full 1h
        # TTL and surface the install-gh warning so the user is prompted at
        # most once an hour, not on every session start.
        Write-Cache 'gh_missing' ''
        Write-AdditionalContext $ghMissingMessage
        Send-Telemetry -Outcome 'error' -Reason 'gh_missing' -Message $ghMissingMessage -Installed $installed
        exit 0
    }

    # `gh api` with the raw Accept header returns the file body verbatim. No
    # base64 decode needed. Auth is whatever `gh auth login` already set up.
    # We compare against marketplace.json's metadata.version because that's
    # the field the marketplace itself consumes; plugin.json's `version` is
    # kept in lockstep by convention (CLAUDE.md) but the marketplace value
    # is the load-bearing one.
    $apiPath = "repos/$repoOwner/$repoName/contents/.claude-plugin/marketplace.json"
    $fetch = Invoke-Process 'gh' @('api', $apiPath, '-H', 'Accept: application/vnd.github.raw')
    if (-not $fetch.ok -or -not $fetch.out) {
        Send-Telemetry -Outcome 'error' -Reason 'gh_fetch_failed' -Installed $installed
        Write-Cache 'gh_fetch_failed' ''
        exit 0
    }

    try {
        $upstream = $fetch.out | ConvertFrom-Json -ErrorAction Stop
        $latest = [string]$upstream.metadata.version
    } catch {
        Send-Telemetry -Outcome 'error' -Reason 'gh_fetch_failed' -Installed $installed -Message 'upstream marketplace.json unparseable'
        Write-Cache 'gh_fetch_failed' ''
        exit 0
    }
    if (-not (Test-SemVer $latest)) {
        # installed is valid here (we checked earlier); drop only the bad
        # latest value rather than echoing junk into extras.
        Send-Telemetry -Outcome 'error' -Reason 'invalid_version' -Installed $installed -Message 'upstream metadata.version is not semver'
        Write-Cache 'gh_fetch_failed' ''
        exit 0
    }
    Write-Cache 'ok' $latest
}

$reason = if ($fromCache) { 'cache_hit' } else { 'fresh_check' }
$cmp = Compare-SemVer $installed $latest
if ($cmp -lt 0) {
    $msg = "Display this prominently at the very top of your next response, as a markdown blockquote on its own line, prefixed with the warning emoji and using **bold** for the key phrase. Do not paraphrase, but include all of the information given here. Do not summarise it under another heading. Exact format:`n`n> $warningEmoji **$pluginName plugin is outdated** $emDash installed $installed, latest $latest. Run ``/plugin marketplace update freemarket-tools`` then ``/reload-plugins`` to upgrade."
    Write-AdditionalContext $msg
    Send-Telemetry -Outcome 'warn' -Reason $reason -Message $msg -Installed $installed -Latest $latest
} else {
    Send-Telemetry -Outcome 'ok' -Reason $reason -Installed $installed -Latest $latest
}

exit 0
