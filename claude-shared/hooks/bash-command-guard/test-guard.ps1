<#
.SYNOPSIS
    Test harness for bash-command-guard.ps1.

.DESCRIPTION
    Default mode (no args): loads test-cases.json, runs every case through
    the hook, prints pass/fail per case, exits non-zero if any case fails.

    Override mode:
      .\test-guard.ps1 -Command "<text>"             Run one command.
      .\test-guard.ps1 -Command "<text>" -WithLogging Same but emit DD log.

    DD logging is suppressed by default so test runs don't pollute the
    dashboard.
#>

[CmdletBinding()]
param(
    [string]$Command,
    [switch]$WithLogging
)

$scriptDir  = $PSScriptRoot
$hookScript = Join-Path $scriptDir 'bash-command-guard.ps1'
$casesPath  = Join-Path $scriptDir 'test-cases.json'

function Invoke-OneCase {
    param(
        [string]$Cmd,
        [string]$ToolName  = 'Bash',
        [string]$RawPayload = ''
    )

    if ($RawPayload) {
        $payload = $RawPayload
    } else {
        $payload = @{
            tool_name  = $ToolName
            tool_input = @{ command = $Cmd }
        } | ConvertTo-Json -Compress
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName  = (Get-Command powershell.exe).Source
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$hookScript`""
    $psi.UseShellExecute        = $false
    $psi.RedirectStandardInput  = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.CreateNoWindow         = $true
    $psi.EnvironmentVariables['BASH_GUARD_TEST_MODE'] = '1'
    $psi.EnvironmentVariables['BASH_GUARD_NO_LOG']    = if ($WithLogging) { '0' } else { '1' }

    $proc = [System.Diagnostics.Process]::Start($psi)
    $proc.StandardInput.Write($payload)
    $proc.StandardInput.Close()
    $stdout = $proc.StandardOutput.ReadToEnd()
    $null = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()

    $lines = @($stdout -split "`r?`n" | Where-Object { $_ })
    $line  = if ($lines.Count -gt 0) { $lines[0] } else { '' }
    $parts = $line -split "`t", 2
    [pscustomobject]@{
        Outcome = if ($parts.Count -ge 1) { $parts[0] } else { '' }
        Pattern = if ($parts.Count -ge 2) { $parts[1] } else { '' }
        Exit    = $proc.ExitCode
    }
}

if ($Command) {
    $r = Invoke-OneCase -Cmd $Command
    switch ($r.Outcome) {
        'block' { "BLOCKED  pattern=$($r.Pattern)  exit=$($r.Exit)" }
        'warn'  { "WARNED   pattern=$($r.Pattern)  exit=$($r.Exit)" }
        'allow' { "ALLOWED                exit=$($r.Exit)" }
        default { "UNKNOWN  outcome='$($r.Outcome)'  exit=$($r.Exit)" }
    }
    exit 0
}

if (-not (Test-Path -LiteralPath $casesPath)) {
    Write-Error "test-cases.json not found at $casesPath"
    exit 2
}

$cases = Get-Content -LiteralPath $casesPath -Raw | ConvertFrom-Json
$pass = 0; $fail = 0
Write-Host "Running $($cases.Count) cases..."
Write-Host ''

foreach ($c in $cases) {
    $caseTool       = if ($c.PSObject.Properties['tool_name']  -and $c.tool_name)  { [string]$c.tool_name } else { 'Bash' }
    $caseRawPayload = if ($c.PSObject.Properties['raw_payload'] -and $c.raw_payload) { [string]$c.raw_payload } else { '' }
    $caseCommand    = if ($c.PSObject.Properties['command']    -and $c.command)    { [string]$c.command } else { '' }
    $caseLabel      = if ($c.PSObject.Properties['label']      -and $c.label)      { [string]$c.label } elseif ($caseCommand) { $caseCommand } else { $caseRawPayload }

    $r = Invoke-OneCase -Cmd $caseCommand -ToolName $caseTool -RawPayload $caseRawPayload
    $expectedPattern = if ($c.pattern) { [string]$c.pattern } else { '' }

    if ($r.Outcome -eq $c.expected) {
        if ($c.expected -eq 'allow' -or -not $expectedPattern -or $r.Pattern -eq $expectedPattern) {
            $pass++
            $extra = if ($r.Outcome -ne 'allow') { " ($($r.Pattern))" } else { '' }
            Write-Host "  [PASS] $caseLabel -> $($r.Outcome)$extra"
        } else {
            $fail++
            Write-Host "  [FAIL] $caseLabel -> $($r.Outcome) but matched $($r.Pattern), expected pattern $expectedPattern"
        }
    } else {
        $fail++
        $actualExtra = if ($r.Outcome -ne 'allow') { " ($($r.Pattern))" } else { '' }
        $expectedExtra = if ($expectedPattern) { " ($expectedPattern)" } else { '' }
        Write-Host "  [FAIL] $caseLabel -> got $($r.Outcome)$actualExtra, expected $($c.expected)$expectedExtra"
    }
}

Write-Host ''
Write-Host "Results: $pass passed, $fail failed (of $($cases.Count))"
if ($fail -gt 0) { exit 1 }
exit 0
