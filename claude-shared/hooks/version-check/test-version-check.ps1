<#
.SYNOPSIS
    Standalone test harness for version-check.ps1.

.DESCRIPTION
    Stages a temporary plugin root, mocks the upstream fetch by priming
    the cache file, and exercises every interesting path:

      1. up-to-date     → exit 0, no stdout
      2. stale          → exit 0, additionalContext JSON on stdout
      3. gh_missing     → exit 0, install-gh additionalContext on stdout
      4. negative cache → exit 0, no stdout
      5. invalid version → exit 0, no stdout (fail-open)
      6. missing plugin.json → exit 0, no stdout (fail-open)

    The harness does NOT exercise the real network — that's covered by the
    manual test recipes in README.md. This file's job is to lock down the
    version-comparison and stdout shape so refactors don't silently regress.

    Run from the plugin root:
        powershell.exe -NoProfile -File hooks/version-check/test-version-check.ps1
#>

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$script = Join-Path $PSScriptRoot 'version-check.ps1'
$failures = @()

function New-PluginRoot {
    param([string]$Version)
    $root = Join-Path ([IO.Path]::GetTempPath()) ("vc-test-" + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path (Join-Path $root '.claude-plugin') -Force | Out-Null
    @{
        name     = 'freemarket-tools'
        metadata = @{ version = $Version }
    } | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $root '.claude-plugin\marketplace.json')
    return $root
}

function Set-Cache {
    param([string]$Outcome, [string]$LatestVersion, [int]$AgeSeconds = 30, [string]$Reason = 'network')
    $cachePath = Join-Path $env:TEMP 'freemarket-claude-skills-version-check.json'
    $checked = (Get-Date).ToUniversalTime().AddSeconds(-$AgeSeconds).ToString('o')
    $obj = if ($Outcome -eq 'ok') {
        @{ checked_at = $checked; outcome = 'ok'; latest_version = $LatestVersion }
    } else {
        @{ checked_at = $checked; outcome = $Outcome; reason = $Reason }
    }
    $obj | ConvertTo-Json -Compress | Set-Content -LiteralPath $cachePath -Encoding UTF8 -NoNewline
    return $cachePath
}

function Remove-Cache {
    Remove-Item (Join-Path $env:TEMP 'freemarket-claude-skills-version-check.json') -ErrorAction SilentlyContinue
}

function Invoke-Hook {
    param([string]$PluginRoot)
    $env:CLAUDE_PLUGIN_ROOT = $PluginRoot
    try {
        $stdout = & powershell.exe -NoProfile -File $script 2>$null
        return @{ stdout = ($stdout -join "`n"); exit = $LASTEXITCODE }
    } finally {
        $env:CLAUDE_PLUGIN_ROOT = $null
    }
}

function Assert-Test {
    param([string]$Name, [bool]$Pass, [string]$Detail = '')
    if ($Pass) {
        Write-Host "  PASS  $Name"
    } else {
        Write-Host "  FAIL  $Name  $Detail" -ForegroundColor Red
        $script:failures += $Name
    }
}

Write-Host 'version-check.ps1 — standalone tests'

# 1. up-to-date (cache primed with same version)
Remove-Cache
$root = New-PluginRoot -Version '1.21.0'
Set-Cache -Outcome 'ok' -LatestVersion '1.21.0' | Out-Null
$r = Invoke-Hook -PluginRoot $root
Assert-Test 'up-to-date emits no stdout' ($r.stdout.Trim() -eq '') "stdout='$($r.stdout)'"
Assert-Test 'up-to-date exits 0'         ($r.exit -eq 0)         "exit=$($r.exit)"

# 2. stale (cache primed with newer upstream)
Remove-Cache
$root = New-PluginRoot -Version '1.0.0'
Set-Cache -Outcome 'ok' -LatestVersion '1.21.0' | Out-Null
$r = Invoke-Hook -PluginRoot $root
$jsonOk = $false
$ctx = $null
try {
    $parsed = $r.stdout | ConvertFrom-Json -ErrorAction Stop
    $ctx = [string]$parsed.hookSpecificOutput.additionalContext
    $jsonOk = $parsed.hookSpecificOutput.hookEventName -eq 'SessionStart'
} catch { }
Assert-Test 'stale emits parseable JSON'                         $jsonOk
Assert-Test 'stale additionalContext mentions both versions'     ($ctx -match '1\.0\.0' -and $ctx -match '1\.21\.0')
Assert-Test 'stale additionalContext mentions /plugin update'    ($ctx -match '/plugin update')
Assert-Test 'stale exits 0'                                       ($r.exit -eq 0)

# 3. gh_missing cache hit — should warn (install-gh JSON) but never call the network
Remove-Cache
$root = New-PluginRoot -Version '1.21.0'
Set-Cache -Outcome 'gh_missing' -LatestVersion '' -AgeSeconds 60 -Reason 'gh_not_on_path' | Out-Null
$r = Invoke-Hook -PluginRoot $root
$ghJsonOk = $false
$ghCtx = $null
try {
    $parsed = $r.stdout | ConvertFrom-Json -ErrorAction Stop
    $ghCtx = [string]$parsed.hookSpecificOutput.additionalContext
    $ghJsonOk = $parsed.hookSpecificOutput.hookEventName -eq 'SessionStart'
} catch { }
Assert-Test 'gh_missing emits parseable JSON'                $ghJsonOk
Assert-Test 'gh_missing additionalContext mentions gh'       ($ghCtx -match 'GitHub CLI' -or $ghCtx -match 'gh')
Assert-Test 'gh_missing additionalContext mentions auth'     ($ghCtx -match 'gh auth login')
Assert-Test 'gh_missing exits 0'                              ($r.exit -eq 0)

# 4. negative cache (recent gh_fetch_failed) — should silently exit 0, never warn
Remove-Cache
$root = New-PluginRoot -Version '1.0.0'
Set-Cache -Outcome 'gh_fetch_failed' -LatestVersion '' -AgeSeconds 60 | Out-Null
$r = Invoke-Hook -PluginRoot $root
Assert-Test 'negative cache emits no stdout' ($r.stdout.Trim() -eq '') "stdout='$($r.stdout)'"
Assert-Test 'negative cache exits 0'         ($r.exit -eq 0)

# 5. invalid installed version — fail-open
Remove-Cache
$root = New-PluginRoot -Version 'not-a-semver'
$r = Invoke-Hook -PluginRoot $root
Assert-Test 'invalid installed version emits no stdout' ($r.stdout.Trim() -eq '') "stdout='$($r.stdout)'"
Assert-Test 'invalid installed version exits 0'         ($r.exit -eq 0)

# 6. missing marketplace.json — fail-open
Remove-Cache
$root = Join-Path ([IO.Path]::GetTempPath()) ("vc-test-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root -Force | Out-Null
$r = Invoke-Hook -PluginRoot $root
Assert-Test 'missing marketplace.json emits no stdout' ($r.stdout.Trim() -eq '') "stdout='$($r.stdout)'"
Assert-Test 'missing marketplace.json exits 0'         ($r.exit -eq 0)

# 7. Byte-level encoding check via cmd-redirected capture. Regression test for
# the Windows PowerShell 5.1 stdout-redirection-encoding bug that hit
# production: PS 5.1 encodes redirected stdout as UTF-16 LE + BOM by default,
# Claude Code reads stdout as UTF-8, sees `FF FE 7B 00 ...` and silently
# drops the additionalContext. The other tests in this harness CAN'T catch
# this regression because `& powershell.exe -File` capture decodes via the
# host's encoding and is BOM-tolerant. Capture via cmd.exe to preserve the
# raw byte stream Claude Code actually sees.
Remove-Cache
$root = New-PluginRoot -Version '1.0.0'
Set-Cache -Outcome 'ok' -LatestVersion '1.21.0' | Out-Null
$bin = Join-Path ([IO.Path]::GetTempPath()) ("vc-bytes-" + [Guid]::NewGuid().ToString('N') + '.bin')
$dispatcher = Join-Path (Split-Path -Parent $script) 'version-check.cmd'
$env:CLAUDE_PLUGIN_ROOT = $root
try {
    # Use ProcessStartInfo directly — Start-Process's ArgumentList re-quotes
    # in surprising ways when a single arg contains multiple `"`. cmd /s /c
    # tells cmd.exe to strip exactly one outer pair of quotes regardless of
    # how many quotes appear inside, which is what we need for redirection
    # of a quoted source path to a quoted destination path.
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = 'cmd.exe'
    $psi.Arguments = '/s /c "' + '"' + $dispatcher + '" > "' + $bin + '"' + '"'
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $cp = [Diagnostics.Process]::Start($psi)
    $cp.WaitForExit()
} finally {
    $env:CLAUDE_PLUGIN_ROOT = $null
}
$bs = if (Test-Path -LiteralPath $bin) { [IO.File]::ReadAllBytes($bin) } else { @() }
$firstByte = if ($bs.Length -gt 0) { $bs[0] } else { 0 }
Assert-Test 'byte stream starts with `{` not BOM' ($firstByte -eq 0x7B) ("first=0x{0:X2} count={1}" -f $firstByte, $bs.Length)
$hasNullBytes = $false
for ($i = 0; $i -lt [Math]::Min($bs.Length, 32); $i++) { if ($bs[$i] -eq 0) { $hasNullBytes = $true; break } }
Assert-Test 'no interleaved null bytes (UTF-16 marker)' (-not $hasNullBytes)
Remove-Item -LiteralPath $bin -ErrorAction SilentlyContinue

Remove-Cache

if ($failures.Count -gt 0) {
    Write-Host ""
    Write-Host "FAILED: $($failures.Count) test(s)" -ForegroundColor Red
    exit 1
}
Write-Host ""
Write-Host "ALL TESTS PASSED" -ForegroundColor Green
exit 0
