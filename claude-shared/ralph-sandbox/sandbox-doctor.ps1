#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Pre-flight health check for Ralph sandbox runs.

.DESCRIPTION
    Validates that the local environment is ready for a Ralph sandbox session.
    Checks Docker, line endings, disk space, NuGet config, and stale artifacts.

.PARAMETER Fix
    Auto-remediate fixable issues instead of just reporting them.

.EXAMPLE
    .\sandbox-doctor.ps1           # Report only
    .\sandbox-doctor.ps1 -Fix      # Auto-remediate
#>

param(
    [switch]$Fix
)

$ErrorActionPreference = 'Continue'
$script:PassCount = 0
$script:WarnCount = 0
$script:FailCount = 0

. "$PSScriptRoot/_azure-constants.ps1"

function Write-Check {
    param(
        [ValidateSet('PASS', 'WARN', 'FAIL')]
        [string]$Status,
        [string]$Message
    )

    switch ($Status) {
        'PASS' { Write-Host "  [PASS] $Message" -ForegroundColor Green; $script:PassCount++ }
        'WARN' { Write-Host "  [WARN] $Message" -ForegroundColor Yellow; $script:WarnCount++ }
        'FAIL' { Write-Host "  [FAIL] $Message" -ForegroundColor Red; $script:FailCount++ }
    }
}

# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------

function Test-PowerShellCore {
    if ($PSVersionTable.PSEdition -eq 'Core') {
        Write-Check PASS "PowerShell Core $($PSVersionTable.PSVersion)"
    } else {
        Write-Check FAIL "Running Windows PowerShell — pwsh (PowerShell Core) is required"
    }
}

function Test-DockerRunning {
    try {
        $info = docker info --format '{{.ServerVersion}}' 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Check PASS "Docker is running (v$info)"
        } else {
            Write-Check FAIL "Docker is not running or not installed"
        }
    } catch {
        Write-Check FAIL "Docker is not running or not installed"
    }
}

function Test-DockerSandboxSupport {
    try {
        docker sandbox ls 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Check PASS "Docker sandbox support detected"
        } else {
            Write-Check WARN "Docker sandbox command not available — upgrade Docker Desktop to 4.40+"
        }
    } catch {
        Write-Check WARN "Docker sandbox command not available — upgrade Docker Desktop to 4.40+"
    }
}

function Test-LineEndings {
    $gitRoot = git rev-parse --show-toplevel 2>$null
    if (-not $gitRoot) {
        Write-Check WARN "Not in a git repository — skipping .gitattributes check"
        return
    }

    $gitattributes = Join-Path $gitRoot '.gitattributes'
    if (Test-Path $gitattributes) {
        $content = Get-Content $gitattributes -Raw
        if ($content -match '\*\s+text=auto') {
            Write-Check PASS ".gitattributes has line ending normalisation (text=auto)"
        } else {
            Write-Check WARN ".gitattributes exists but missing '* text=auto' directive"
        }
    } else {
        Write-Check WARN ".gitattributes not found — line endings may cause noise in diffs"
    }
}

function Test-DiskSpace {
    try {
        $drive = (Get-Location).Drive
        if ($drive) {
            $freeGB = [math]::Round($drive.Free / 1GB, 1)
            if ($freeGB -ge 10) {
                Write-Check PASS "$($freeGB)GB free disk space"
            } else {
                Write-Check WARN "Only $($freeGB)GB free disk space (recommend 10GB+ for Docker images)"
            }
        } else {
            Write-Check WARN "Could not determine disk space"
        }
    } catch {
        Write-Check WARN "Could not determine disk space"
    }
}

function Test-NuGetConfig {
    $nugetConfig = Join-Path $env:USERPROFILE '.nuget' 'NuGet' 'NuGet.Config'
    if (-not (Test-Path $nugetConfig)) {
        Write-Check PASS "No user-level NuGet.Config (using defaults)"
        return
    }

    try {
        [xml]$xml = Get-Content $nugetConfig
        $fallbackFolders = $xml.configuration.fallbackPackageFolders
        if ($null -eq $fallbackFolders) {
            Write-Check PASS "NuGet config OK (no fallback folders)"
            return
        }

        $brokenFolders = @()
        foreach ($add in $fallbackFolders.add) {
            if ($add.value -and -not (Test-Path $add.value)) {
                $brokenFolders += $add.value
            }
        }

        if ($brokenFolders.Count -gt 0) {
            Write-Check WARN "NuGet fallback folders point to missing paths: $($brokenFolders -join ', ')"
        } else {
            Write-Check PASS "NuGet config OK"
        }
    } catch {
        Write-Check WARN "Could not parse NuGet.Config: $_"
    }
}

function Test-DockerCleanup {
    try {
        $danglingImages = docker images -f "dangling=true" -q 2>$null
        $danglingCount = if ($danglingImages) { ($danglingImages -split "`n").Count } else { 0 }

        if ($danglingCount -eq 0) {
            Write-Check PASS "No dangling Docker images"
        } elseif ($Fix) {
            docker image prune -f 2>&1 | Out-Null
            Write-Check PASS "Pruned $danglingCount dangling Docker images"
        } else {
            Write-Check WARN "$danglingCount dangling Docker images (run with -Fix to prune, or: docker image prune -f)"
        }
    } catch {
        Write-Check WARN "Could not check Docker images"
    }
}

function Test-OrphanedSandboxState {
    # Detects stale state that causes `docker sandbox create` to fail with:
    #   "failed to load template image: no Docker context found for sandbox <name>"
    # Two independent orphan sources, both invisible to `docker sandbox ls` / `docker context ls`:
    #   1. VM dir at ~/.docker/sandboxes/vm/<name>/ with no live VM.
    #   2. Context meta dir at ~/.docker/contexts/meta/<sha256(name)>/ with empty/missing meta.json.
    # The daemon sees both and refuses to reuse the name. Upstream: no `docker sandbox prune` yet.

    $vmRoot = Join-Path $env:USERPROFILE '.docker\sandboxes\vm'
    $ctxRoot = Join-Path $env:USERPROFILE '.docker\contexts\meta'

    # Live sandbox names (skip header row)
    $liveNames = @()
    try {
        $lsOutput = docker sandbox ls 2>$null
        if ($LASTEXITCODE -eq 0 -and $lsOutput) {
            $liveNames = $lsOutput | Select-Object -Skip 1 |
                         ForEach-Object { ($_ -split '\s+', 2)[0] } |
                         Where-Object { $_ }
        }
    } catch { }

    # Orphan VM dirs: directory present, name not in `docker sandbox ls`
    $orphanVmDirs = @()
    if (Test-Path $vmRoot) {
        $orphanVmDirs = Get-ChildItem -Path $vmRoot -Directory -ErrorAction SilentlyContinue |
                        Where-Object { $liveNames -notcontains $_.Name }
    }

    # Orphan context meta dirs: meta.json empty or missing
    $orphanCtxDirs = @()
    if (Test-Path $ctxRoot) {
        $orphanCtxDirs = Get-ChildItem -Path $ctxRoot -Directory -ErrorAction SilentlyContinue |
                         Where-Object {
                             $metaFile = Join-Path $_.FullName 'meta.json'
                             -not (Test-Path $metaFile) -or (Get-Item $metaFile).Length -eq 0
                         }
    }

    $orphanCount = $orphanVmDirs.Count + $orphanCtxDirs.Count
    if ($orphanCount -eq 0) {
        Write-Check PASS "No orphaned sandbox state"
        return
    }

    if ($Fix) {
        foreach ($d in $orphanVmDirs) {
            Remove-Item -Recurse -Force $d.FullName -ErrorAction SilentlyContinue
        }
        foreach ($d in $orphanCtxDirs) {
            Remove-Item -Recurse -Force $d.FullName -ErrorAction SilentlyContinue
        }
        $vmNames = ($orphanVmDirs | ForEach-Object { $_.Name }) -join ', '
        $msg = "Removed $($orphanVmDirs.Count) orphan VM dir(s)"
        if ($vmNames) { $msg += " [$vmNames]" }
        $msg += " and $($orphanCtxDirs.Count) orphan context dir(s)"
        Write-Check PASS $msg
    } else {
        $vmNames = ($orphanVmDirs | ForEach-Object { $_.Name }) -join ', '
        if ($orphanVmDirs.Count -gt 0) {
            Write-Check WARN "$($orphanVmDirs.Count) orphan VM dir(s) under .docker\sandboxes\vm: $vmNames"
        }
        if ($orphanCtxDirs.Count -gt 0) {
            Write-Check WARN "$($orphanCtxDirs.Count) orphan context dir(s) with empty meta.json under .docker\contexts\meta (run with -Fix to remove)"
        }
    }
}

function Test-ClaudeCredentials {
    $credsPath = Join-Path $env:USERPROFILE '.claude' '.credentials.json'
    if (Test-Path $credsPath) {
        Write-Check PASS "Claude credentials found"
    } else {
        Write-Check FAIL "Claude credentials not found at $credsPath — run 'claude auth login'"
    }
}

function Test-ClaudeCliAvailable {
    try {
        $version = claude --version 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Check PASS "Claude CLI available ($version)"
        } else {
            Write-Check WARN "Claude CLI not responding"
        }
    } catch {
        Write-Check WARN "Claude CLI not found in PATH"
    }
}

function Test-AzureAuth {
    $RequiredTenantId       = $script:RalphAzureTenantId
    $RequiredSubscriptionId = $script:RalphAzureSubscriptionId

    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        Write-Check FAIL "Azure CLI not installed — https://aka.ms/installazurecli"
        return
    }

    $account = $null
    try {
        $account = az account show 2>$null | ConvertFrom-Json -ErrorAction SilentlyContinue
    } catch { }

    if (-not $account) {
        Write-Check FAIL "Not logged into Azure — run: az login --tenant $RequiredTenantId"
        return
    }

    if ($account.tenantId -ne $RequiredTenantId) {
        Write-Check FAIL "Logged into wrong tenant ($($account.tenantId)); expected $RequiredTenantId — run: az login --tenant $RequiredTenantId"
        return
    }

    $tokenJson = $null
    try {
        $tokenJson = az account get-access-token --tenant $RequiredTenantId 2>$null | ConvertFrom-Json -ErrorAction SilentlyContinue
    } catch { }

    if (-not $tokenJson -or -not $tokenJson.expiresOn) {
        Write-Check FAIL "Azure token unobtainable — run: az login --tenant $RequiredTenantId"
        return
    }

    try {
        $expires = [datetime]$tokenJson.expiresOn
        if ($expires -lt (Get-Date)) {
            Write-Check FAIL "Azure token expired at $expires — run: az login --tenant $RequiredTenantId"
            return
        }
    } catch {
        Write-Check FAIL "Could not parse Azure token expiry — run: az login --tenant $RequiredTenantId"
        return
    }

    if ($account.id -ne $RequiredSubscriptionId) {
        Write-Check WARN "Active subscription $($account.id); expected $RequiredSubscriptionId — run: az account set --subscription $RequiredSubscriptionId"
        return
    }

    Write-Check PASS "Azure CLI authenticated (tenant + subscription + token)"
}

function Test-KeeperSecretsFile {
    $keeperPath = Join-Path $env:USERPROFILE '.claude' '.keeper'
    if (Test-Path $keeperPath) {
        Write-Check PASS "Keeper secrets file found"
    } else {
        Write-Check WARN "Keeper secrets file not found at $keeperPath — sandbox KSM import will fail"
    }
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

Write-Host ""
Write-Host "  Sandbox Doctor" -ForegroundColor Cyan
Write-Host "  =============" -ForegroundColor Cyan
Write-Host ""

Test-PowerShellCore
Test-DockerRunning
Test-DockerSandboxSupport
Test-LineEndings
Test-DiskSpace
Test-NuGetConfig
Test-DockerCleanup
Test-OrphanedSandboxState
Test-ClaudeCredentials
Test-ClaudeCliAvailable
Test-AzureAuth
Test-KeeperSecretsFile

Write-Host ""
Write-Host "  ─────────────────────────────────────────" -ForegroundColor DarkGray
$summary = "  $script:PassCount passed, $script:WarnCount warnings, $script:FailCount failures"
if ($script:FailCount -gt 0) {
    Write-Host $summary -ForegroundColor Red
} elseif ($script:WarnCount -gt 0) {
    Write-Host $summary -ForegroundColor Yellow
} else {
    Write-Host $summary -ForegroundColor Green
}
Write-Host ""

exit $(if ($script:FailCount -gt 0) { 1 } else { 0 })
