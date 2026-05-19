<#
.SYNOPSIS
    Build the ralph-sandbox Docker image locally.
.DESCRIPTION
    Replicates the CI build (build-sandbox-image.yml) on a local machine.
    Pulls the base image and builds the image tagged as :latest.  Does NOT push.

    By default, Az login and KSM config fetch are skipped. Pass -FetchSecrets
    to authenticate against Azure and pull the KSM config from Key Vault.
.PARAMETER FetchSecrets
    When set, logs into Azure CLI and fetches the KSM config from Key Vault,
    writing it to ~/.claude/.keeper.
.EXAMPLE
    ralph-sandbox/docker/build-local.ps1
.EXAMPLE
    ralph-sandbox/docker/build-local.ps1 -FetchSecrets
#>
[CmdletBinding()]
param(
    [switch]$FetchSecrets
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ImageName = 'ralph-sandbox'
$BaseImage = 'docker/sandbox-templates:claude-code'

# Resolve repo root (build context must be the repo root, same as CI context: .)
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RepoRoot  = Resolve-Path (Join-Path $ScriptDir '..\..')

if ($FetchSecrets) {
    . "$ScriptDir/../_azure-constants.ps1"
    # --- Ensure Azure CLI is logged into the correct tenant ---
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

    Write-Host 'Fetching KSM config from Key Vault ...'
    $KsmConfig = az keyvault secret show `
        --vault-name fmfxukdevinfrakv `
        --name claude-docker-sandbox-ksm-config `
        --query value -o tsv
    if ($LASTEXITCODE -ne 0) { throw 'Failed to fetch KSM config from Key Vault.' }

    $KeeperDir = Join-Path $env:USERPROFILE '.claude'
    $KeeperFile = Join-Path $KeeperDir '.keeper'
    if (-not (Test-Path $KeeperDir)) { New-Item -ItemType Directory -Path $KeeperDir -Force | Out-Null }
    Set-Content -Path $KeeperFile -Value $KsmConfig -NoNewline
    Write-Host "KSM config written to $KeeperFile" -ForegroundColor Green
}

Write-Host "Pulling base image: $BaseImage"
docker pull $BaseImage
if ($LASTEXITCODE -ne 0) { throw "Failed to pull base image" }

Write-Host "Building $ImageName from context $RepoRoot ..."

docker build `
    -f "$RepoRoot/ralph-sandbox/docker/Dockerfile.sandbox" `
    --build-arg SCRIPT_DIR=ralph-sandbox `
    -t "${ImageName}:latest" `
    $RepoRoot

if ($LASTEXITCODE -ne 0) { throw "Docker build failed" }

Write-Host ''
Write-Host "Build succeeded. Tagged image: ${ImageName}:latest"
