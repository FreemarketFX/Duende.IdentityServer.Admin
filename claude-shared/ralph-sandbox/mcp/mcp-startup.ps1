<#
.SYNOPSIS
    Starts (or stops) Docker-based MCP servers for local Claude Code development.

.DESCRIPTION
    Lightweight alternative to ralph-sandbox.ps1 — just docker compose up + .mcp.json generation.
    No image caching, no sandbox overlays, no proxy config.

.PARAMETER Down
    Stop all Docker-based MCP servers and remove .mcp.json.

.EXAMPLE
    # Start servers and generate .mcp.json
    ./compose-startup.ps1

    # Stop servers and remove .mcp.json
    ./compose-startup.ps1 -Down
#>
param([switch]$Down)

$ErrorActionPreference = "Stop"

# --- Resolve paths ---
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RepoRoot  = (Resolve-Path (Join-Path $ScriptDir "../../..")).Path
$ConfigDir = Join-Path $RepoRoot "tasks/config"

# --- Install/import powershell-yaml ---
if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
    Write-Host "Installing powershell-yaml module..."
    Install-Module -Name powershell-yaml -Force -Scope CurrentUser
}
Import-Module powershell-yaml

# --- Check Docker is available ---
try {
    docker version --format '{{.Server.Version}}' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw }
} catch {
    Write-Error "Docker is not available. Ensure Docker Desktop is running."
    exit 1
}

# --- Load MCP manifest ---
$McpManifest = Join-Path $ConfigDir "mcp-servers.yml"
if (-not (Test-Path $McpManifest)) {
    Write-Error "MCP manifest not found: $McpManifest"
    exit 1
}
$manifest = ConvertFrom-Yaml (Get-Content $McpManifest -Raw)

# --- Collect Docker-based servers ---
$dockerServers = @()
foreach ($name in $manifest.servers.Keys) {
    $server = $manifest.servers[$name]
    if ($server.docker -and $server.docker.compose) {
        $composeFile = Join-Path $ScriptDir $server.docker.compose
        if (-not (Test-Path $composeFile)) {
            Write-Error "Compose file not found: $composeFile"
            exit 1
        }
        $dockerServers += @{
            Name        = $name
            ComposeFile = $composeFile
        }
    }
}

# --- ConvertTo-AllowedOrigins: domain patterns → semicolon-separated origins ---
function ConvertTo-AllowedOrigins {
    param([string[]]$Domains)
    $origins = @()
    foreach ($domain in $Domains) {
        if ($domain -match ':(\d+)$') {
            $port = [int]$Matches[1]
            $hostPart = $domain -replace ':\d+$', ''
            if ($port -eq 443) {
                $origins += "https://$hostPart"
            } elseif ($port -eq 80) {
                $origins += "http://$hostPart"
            } else {
                $origins += "https://${hostPart}:${port}"
                $origins += "http://${hostPart}:${port}"
            }
        } else {
            $origins += "https://$domain"
            $origins += "http://$domain"
        }
    }
    return ($origins -join ";")
}

# --- Load proxy-config and set allowed-origins env vars ---
$ProxyConfigPath = Join-Path $RepoRoot "claude-shared/ralph-sandbox/config/proxy-config.yml"
if (Test-Path $ProxyConfigPath) {
    $proxyConfig = ConvertFrom-Yaml (Get-Content $ProxyConfigPath -Raw)
    foreach ($name in $manifest.servers.Keys) {
        $server = $manifest.servers[$name]
        if ($server.docker -and $server.docker.allowedOriginsEnvVar -and $server.docker.proxyConfigSection) {
            $envVar  = $server.docker.allowedOriginsEnvVar
            $section = $server.docker.proxyConfigSection
            if ($proxyConfig[$section] -and $proxyConfig[$section].allowedDomains) {
                $originsString = ConvertTo-AllowedOrigins $proxyConfig[$section].allowedDomains
                [System.Environment]::SetEnvironmentVariable($envVar, $originsString, "Process")
                Write-Host "Set $envVar = $originsString"
            } else {
                Write-Host "No allowedDomains in proxy-config section '$section' — $envVar left unset (unrestricted)"
            }
        }
    }
} else {
    Write-Host "No proxy-config.yml found — domain restrictions disabled (unrestricted)"
}

$mcpJsonPath = Join-Path $RepoRoot ".mcp.json"

# =============================================================================
# DOWN MODE
# =============================================================================
if ($Down) {
    foreach ($ds in $dockerServers) {
        Write-Host "Stopping $($ds.Name)..."
        docker compose -f $ds.ComposeFile down 2>&1 | ForEach-Object { Write-Host "  $_" }
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Failed to stop $($ds.Name) — continuing teardown"
        }
    }

    if (Test-Path $mcpJsonPath) {
        Remove-Item $mcpJsonPath -Force
        Write-Host "Removed $mcpJsonPath"
    }

    Write-Host "Done."
    exit 0
}

# =============================================================================
# START MODE
# =============================================================================

# --- Start Docker Compose services ---
foreach ($ds in $dockerServers) {
    Write-Host "Starting $($ds.Name)..."
    docker compose -f $ds.ComposeFile up -d --force-recreate 2>&1 | ForEach-Object { Write-Host "  $_" }
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to start $($ds.Name)"
        exit 1
    }
}

# --- Generate .mcp.json ---
$mcpServers = @{}
foreach ($name in $manifest.servers.Keys) {
    $server = $manifest.servers[$name]
    $entry = @{ type = $server.type }
    if ($server.url)     { $entry.url = $server.url }
    if ($server.command) { $entry.command = $server.command }
    if ($server.args)    { $entry.args = $server.args }
    if ($server.env)     { $entry.env = $server.env }
    if ($server.headers) { $entry.headers = $server.headers }
    $mcpServers[$name] = $entry
}

$mcpJson = @{ mcpServers = $mcpServers } | ConvertTo-Json -Depth 5
Set-Content -Path $mcpJsonPath -Value $mcpJson -Encoding UTF8 -Force
Write-Host "Generated $mcpJsonPath"

# --- Resolve ${...} env var references using KSM ---
if ((Get-Content $mcpJsonPath -Raw).Contains('${')) {
    if (-not (Get-Command ksm -ErrorAction SilentlyContinue)) {
        Write-Error "KSM CLI not found. Install it from: https://docs.keeper.io/en/secrets-manager/secrets-manager/secrets-manager-command-line-interface/init-command"
        exit 1
    }

    try {
        . "$PSScriptRoot/../_azure-constants.ps1"
        # Ensure Azure login
        $RequiredTenantId = $script:RalphAzureTenantId
        $currentTenant = $null
        try { $currentTenant = (az account show --query tenantId -o tsv 2>$null) } catch { }
        if ($currentTenant -ne $RequiredTenantId) {
            Write-Host "Azure CLI is not logged into tenant $RequiredTenantId." -ForegroundColor Yellow
            az login --tenant $RequiredTenantId --output none
            if ($LASTEXITCODE -ne 0) { throw 'Azure login failed.' }
        }

        # Ensure correct subscription
        $RequiredSubscriptionId = $script:RalphAzureSubscriptionId
        $currentSub = $null
        try { $currentSub = (az account show --query id -o tsv 2>$null) } catch { }
        if ($currentSub -ne $RequiredSubscriptionId) {
            Write-Host "Switching Azure subscription to $RequiredSubscriptionId..."
            az account set --subscription $RequiredSubscriptionId
            if ($LASTEXITCODE -ne 0) { throw 'Failed to set Azure subscription.' }
        }

        # Fetch KSM config and import profile
        Write-Host "Fetching KSM config from Key Vault..."
        $KsmConfig = az keyvault secret show `
            --vault-name fmfxukdevinfrakv `
            --name claude-docker-sandbox-ksm-config `
            --query value -o tsv
        if ($LASTEXITCODE -ne 0) { throw 'Failed to fetch KSM config from Key Vault.' }
        ksm profile import --profile-name mcp-local "$KsmConfig"

        # Interpolate template to resolve keeper:// URIs
        $templatePath = (Resolve-Path (Join-Path $ScriptDir "../config/sandbox-persistent.template")).Path
        $tempFile = Join-Path $env:TEMP "sandbox-persistent-resolved.sh"
        ksm interpolate $templatePath | Set-Content $tempFile -Encoding UTF8

        # Parse resolved values and substitute into .mcp.json
        $envVars = @{}
        Get-Content $tempFile | ForEach-Object {
            if ($_ -match '^export\s+(\w+)=(.*)$') {
                $envVars[$Matches[1]] = $Matches[2]
            }
        }
        Remove-Item $tempFile -Force

        $json = Get-Content $mcpJsonPath -Raw
        foreach ($key in $envVars.Keys) {
            $json = $json -replace [regex]::Escape("`${$key}"), $envVars[$key]
        }
        Set-Content -Path $mcpJsonPath -Value $json -Encoding UTF8 -Force
        Write-Host "Resolved env var references in .mcp.json"
    } finally {
        ksm profile delete mcp-local 2>$null
        Remove-Item "keeper.ini" -Force -ErrorAction SilentlyContinue
    }
}

# --- Wait for containers to become healthy ---
$timeout = 60
$pollInterval = 5
$containersToCheck = @()

foreach ($ds in $dockerServers) {
    $composeYaml = ConvertFrom-Yaml (Get-Content $ds.ComposeFile -Raw)
    foreach ($svcName in $composeYaml.services.Keys) {
        $svc = $composeYaml.services[$svcName]
        if ($svc.container_name -and $svc.healthcheck) {
            $containersToCheck += @{
                ServerName    = $ds.Name
                ContainerName = $svc.container_name
            }
        }
    }
}

if ($containersToCheck.Count -gt 0) {
    Write-Host ""
    Write-Host "Waiting for containers to become healthy (${timeout}s timeout)..."
    $elapsed = 0
    $healthy = @{}

    while ($elapsed -lt $timeout) {
        $allHealthy = $true
        foreach ($c in $containersToCheck) {
            if ($healthy[$c.ContainerName]) { continue }
            $status = docker inspect --format '{{.State.Health.Status}}' $c.ContainerName 2>$null
            if ($status -eq "healthy") {
                Write-Host "  $($c.ContainerName): healthy"
                $healthy[$c.ContainerName] = $true
            } else {
                $allHealthy = $false
            }
        }
        if ($allHealthy) { break }
        Start-Sleep -Seconds $pollInterval
        $elapsed += $pollInterval
    }

    # Warn about any that didn't become healthy
    foreach ($c in $containersToCheck) {
        if (-not $healthy[$c.ContainerName]) {
            Write-Warning "$($c.ContainerName) did not become healthy within ${timeout}s"
        }
    }
}

# --- Summary ---
Write-Host ""
Write-Host "=== MCP Servers ==="
foreach ($name in $manifest.servers.Keys) {
    $server = $manifest.servers[$name]
    $status = if ($server.docker) { "(Docker)" } else { "($($server.type))" }
    Write-Host "  $name $status -> $($server.url ?? $server.command)"
}
Write-Host ""
Write-Host ".mcp.json written to: $mcpJsonPath"
Write-Host "Done."
