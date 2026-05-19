<#
.SYNOPSIS
    PreToolUse Bash command-guard (Windows).

.DESCRIPTION
    Reads PreToolUse JSON from stdin, extracts tool_input.command, and
    matches it against blocklist.txt and warnlist.txt in this directory.
    Each list entry is a regex (case-insensitive). First block-list match
    -> exit 2 with stderr message + sentinel. First warn-list match ->
    exit 0, log warn only.

    Telemetry is best-effort via the shared Datadog helper. Set
    $env:BASH_GUARD_NO_LOG = '1' to suppress (used by test-guard.ps1).
    Set $env:BASH_GUARD_TEST_MODE = '1' to suppress all stderr output and
    instead print "<outcome>`t<pattern>" to stdout (used by the test runner).

    Compatible with Windows PowerShell 5.1.
#>

trap { exit 0 }

$blocklistPath = Join-Path $PSScriptRoot 'blocklist.txt'
$warnlistPath  = Join-Path $PSScriptRoot 'warnlist.txt'

# Read PreToolUse JSON payload from stdin. Skip when stdin is a console.
$rawStdin = $null
$toolName = 'unknown'
$commandText = ''
if ([Console]::IsInputRedirected) {
    try {
        $rawStdin = [Console]::In.ReadToEnd()
        if ($rawStdin) {
            $payload = $rawStdin | ConvertFrom-Json -ErrorAction Stop
            if ($payload.tool_name) { $toolName = [string]$payload.tool_name }
            if ($payload.tool_input -and $payload.tool_input.command) {
                $commandText = [string]$payload.tool_input.command
            }
        }
    } catch { }
}

function Exit-WithTestAllow {
    if ($env:BASH_GUARD_TEST_MODE -eq '1') {
        [Console]::Out.WriteLine("allow`t")
    }
    exit 0
}

# Defense-in-depth: only inspect Bash. Exit 0 on anything else (or on empty).
if ($toolName -ne 'Bash') { Exit-WithTestAllow }
if (-not $commandText)    { Exit-WithTestAllow }

function Get-PatternList {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    $lines = @()
    foreach ($raw in (Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue)) {
        $line = $raw.Trim()
        if (-not $line) { continue }
        if ($line.StartsWith('#')) { continue }
        $lines += $line
    }
    return ,$lines
}

function Find-Match {
    param([string]$Cmd, [string[]]$Patterns)
    foreach ($pat in $Patterns) {
        try {
            if ([System.Text.RegularExpressions.Regex]::IsMatch(
                    $Cmd, $pat,
                    [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
                return $pat
            }
        } catch {
            # Bad regex — skip silently. The bash side does the same.
        }
    }
    return $null
}

$blockPatterns = Get-PatternList $blocklistPath
$warnPatterns  = Get-PatternList $warnlistPath

$preview = if ($commandText.Length -gt 200) { $commandText.Substring(0, 200) } else { $commandText }

function Send-Log {
    param(
        [string]$Outcome,
        [string]$Reason,
        [string]$Status,
        [string]$Msg,
        [string]$EventName,
        [string]$MatchedPattern
    )
    if ($env:BASH_GUARD_NO_LOG -eq '1') { return }
    try {
        . (Join-Path $PSScriptRoot '..\lib\datadog-log\post.ps1')
        $extra = @{
            source = [ordered]@{
                tool            = 'Bash'
                command         = $commandText
                matched_pattern = $MatchedPattern
            }
        }
        Send-DatadogHookLog `
            -Hook 'bash-command-guard' `
            -HookEvent 'PreToolUse' `
            -ToolName 'Bash' `
            -Outcome $Outcome `
            -Reason $Reason `
            -Status $Status `
            -Message $Msg `
            -EventName $EventName `
            -StdinJson $rawStdin `
            -Extra $extra
    } catch { }
}

$blockHit = Find-Match $commandText $blockPatterns
if ($blockHit) {
    $human = "Blocked: Bash command matched guard pattern '$blockHit'. Report this in #tech-claude-faq if you need assistance. DO NOT ATTEMPT TO CIRCUMVENT OR BYPASS THIS CONTROL."
    $msg = "$human Command preview: $preview"
    # Send-Log first so test mode + -WithLogging surfaces the post.
    # Send-Log self-checks $env:BASH_GUARD_NO_LOG and is fail-open.
    Send-Log -Outcome 'block' -Reason 'blocklist_match' -Status 'error' -Msg $msg `
             -EventName 'hook_block' -MatchedPattern $blockHit
    if ($env:BASH_GUARD_TEST_MODE -eq '1') {
        [Console]::Out.WriteLine("block`t$blockHit")
        exit 2
    }
    $sentinel = "CLAUDE_BASH_GUARD_BLOCK pattern=$blockHit tool=Bash pid=$PID"
    [Console]::Error.WriteLine($human)
    [Console]::Error.WriteLine($sentinel)
    exit 2
}

$warnHit = Find-Match $commandText $warnPatterns
if ($warnHit) {
    $msg = "Warn: Bash command matched warn pattern '$warnHit'. Command preview: $preview"
    Send-Log -Outcome 'warn' -Reason 'warnlist_match' -Status 'warning' -Msg $msg `
             -EventName 'hook_warn' -MatchedPattern $warnHit
    if ($env:BASH_GUARD_TEST_MODE -eq '1') {
        [Console]::Out.WriteLine("warn`t$warnHit")
        exit 0
    }
    exit 0
}

if ($env:BASH_GUARD_TEST_MODE -eq '1') {
    [Console]::Out.WriteLine("allow`t")
}
exit 0
