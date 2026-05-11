#!/usr/bin/env pwsh
# Ralph Teardown - Removes the Docker sandbox for the current repo
# Usage: ./sandbox-teardown.ps1 [-RepoRoot <path>]

param(
    [string]$RepoRoot
)

$ErrorActionPreference = "Stop"

$ScriptDir = $PSScriptRoot

if (-not $RepoRoot) {
    $RepoRoot = (Get-Item $ScriptDir).Parent.Parent.FullName
}

$RepoFolderName = (Get-Item $RepoRoot).Name

# Derive sandbox name using same convention as ralph-sandbox.ps1
$sandboxName = "claude-$RepoFolderName"

Write-Host "Repo:    $RepoRoot"
Write-Host "Sandbox: $sandboxName"
Write-Host ""

# List existing Docker sandboxes
$existingSandboxes = docker sandbox ls -q 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to list Docker sandboxes. Is Docker running?"
    exit 1
}

# Check if our sandbox exists
if ($existingSandboxes -notcontains $sandboxName) {
    Write-Host "No sandbox found for this repo ('$sandboxName'). Nothing to remove."
    exit 0
}

# Prompt user to confirm removal
$confirm = Read-Host "Remove sandbox '$sandboxName'? (Y/N)"
if ($confirm -notin @("Y", "y", "Yes", "yes")) {
    Write-Host "Aborted."
    exit 0
}

# Restore worktree .git file if rewritten by sandbox entrypoint
$gitBackup = Join-Path $RepoRoot ".git.windows-original"
if (Test-Path $gitBackup) {
    Copy-Item $gitBackup (Join-Path $RepoRoot ".git") -Force
    Remove-Item $gitBackup -Force
    Write-Host "Restored worktree .git file"
}

# Remove the sandbox
Write-Host ""
Write-Host "Removing sandbox '$sandboxName'..."
docker sandbox rm $sandboxName 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to remove sandbox '$sandboxName'."
    exit 1
}

Write-Host "Sandbox '$sandboxName' removed successfully."
