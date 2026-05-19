<#
.SYNOPSIS
    Check for and download updated patterns.yaml from Lasso Security.

.DESCRIPTION
    Compares the local patterns.yaml against the upstream version in the
    lasso-security/claude-hooks GitHub repository. If a newer version is
    available, prompts the user to download it.

.PARAMETER Force
    Download without prompting.

.PARAMETER DryRun
    Check for updates without downloading.

.EXAMPLE
    pwsh update-patterns.ps1
    pwsh update-patterns.ps1 -Force
    pwsh update-patterns.ps1 -DryRun
#>

[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$upstreamUrl = 'https://raw.githubusercontent.com/lasso-security/claude-hooks/refs/heads/dev/.claude/skills/prompt-injection-defender/patterns.yaml'
$localPath = Join-Path $PSScriptRoot 'patterns.yaml'

function Normalize-LineEndings([string]$Text) {
    # Normalize CRLF/CR to LF for consistent comparison
    return $Text -replace "`r`n", "`n" -replace "`r", "`n"
}

function Get-FileHash256([string]$Content) {
    $normalized = Normalize-LineEndings $Content
    $stream = [System.IO.MemoryStream]::new([System.Text.Encoding]::UTF8.GetBytes($normalized))
    try {
        return (Get-FileHash -InputStream $stream -Algorithm SHA256).Hash
    }
    finally {
        $stream.Dispose()
    }
}

# Read local patterns
if (-not (Test-Path $localPath)) {
    Write-Host 'No local patterns.yaml found. Downloading from upstream...'
    $Force = $true
}

$localContent = if (Test-Path $localPath) {
    Get-Content -Path $localPath -Raw -Encoding UTF8
} else {
    ''
}

# Fetch upstream patterns
Write-Host "Checking upstream: $upstreamUrl"
try {
    $response = Invoke-WebRequest -Uri $upstreamUrl -UseBasicParsing -ErrorAction Stop
    $upstreamContent = $response.Content
}
catch {
    Write-Host "Failed to fetch upstream patterns: $_" -ForegroundColor Red
    exit 1
}

# Compare
$localHash = if ($localContent) { Get-FileHash256 $localContent } else { '' }
$upstreamHash = Get-FileHash256 $upstreamContent

if ($localHash -eq $upstreamHash) {
    Write-Host 'patterns.yaml is up to date.' -ForegroundColor Green
    exit 0
}

Write-Host 'Updated patterns.yaml available from upstream.' -ForegroundColor Yellow

if ($DryRun) {
    Write-Host '(Dry run - no changes made.)'
    exit 0
}

if (-not $Force) {
    $answer = Read-Host 'Download updated patterns.yaml? [Y/n]'
    if ($answer -and $answer.Trim().ToLower() -notin @('y', 'yes', '')) {
        Write-Host 'Skipped.'
        exit 0
    }
}

# Backup existing file
if (Test-Path $localPath) {
    $backupPath = "$localPath.bak"
    Copy-Item -Path $localPath -Destination $backupPath -Force
    Write-Host "Backed up existing file to $backupPath"
}

# Write new patterns
Set-Content -Path $localPath -Value $upstreamContent -Encoding UTF8 -NoNewline
Write-Host 'patterns.yaml updated successfully.' -ForegroundColor Green
