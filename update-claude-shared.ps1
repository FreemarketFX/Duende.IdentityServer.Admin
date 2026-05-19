# update-claude-shared.ps1
# Run this from within the claude-shared folder of any consuming repo to update the claude-shared subtree

param(
    [string]$Remote = "https://github.com/FreemarketFX/claude-shared.git",
    [string]$Branch = "main",
    [string]$Prefix = "claude-shared"
)

$ErrorActionPreference = "Stop"

# Navigate to the repo root (parent of the folder this script lives in)
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptDir
Push-Location $repoRoot

try {
    # Verify we're at the repo root
    if (-not (Test-Path ".git")) {
        Write-Error "Could not find .git directory at $repoRoot"
        exit 1
    }

    # Check for uncommitted changes (ignore untracked files)
    $status = git status --porcelain | Where-Object { $_ -notmatch '^\?\?' }
    if ($status) {
        Write-Error "You have uncommitted changes. Please commit or stash them first."
        exit 1
    }

    # Pull the subtree
    if (Test-Path $Prefix) {
        Write-Host "Pulling $Remote@$Branch into '$Prefix'..." -ForegroundColor Cyan
        git subtree pull --prefix=$Prefix $Remote $Branch --squash -m "chore(FMFX-13816): Update $Prefix from $Branch"
    } else {
        Write-Error "Could not find $Prefix directory"
        exit 1
    }

    Write-Host "Done. '$Prefix' is up to date." -ForegroundColor Green
}
finally {
    Pop-Location
}