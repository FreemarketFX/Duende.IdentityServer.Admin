<#
.SYNOPSIS
    Launches Windows Terminal with 2-pane dev layout for a project folder.
    Automatically sets tab title and color-codes the profile per repo.
.PARAMETER Project
    Project folder name (under base path) or full path.
.PARAMETER BasePath
    Optional base directory where project folders live. Defaults to C:\dev\freemarket.
    If the default doesn't exist, you'll be prompted for your path on first run.
.PARAMETER NoRalph
    Launch Claude Code only (single pane, no Ralph). Skips Ralph profile setup.
    Useful for discovery, debugging, or exploration sessions.
.EXAMPLE
    .\Start-DevTerminal.ps1 PlatformCode
    .\Start-DevTerminal.ps1 PlatformCode -BasePath C:\Development
    .\Start-DevTerminal.ps1 PlatformCode -NoRalph
    .\Start-DevTerminal.ps1 C:\other\path
#>
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Project,

    [Parameter(Mandatory = $false)]
    [string]$BasePath,

    [switch]$NoRalph
)

$defaultBasePath = "C:\dev\freemarket"

# Resolve base path: explicit param > default > prompt
if ($BasePath) {
    if (-not (Test-Path $BasePath)) {
        Write-Error "Base path not found: $BasePath"
        exit 1
    }
} elseif (Test-Path $defaultBasePath) {
    $BasePath = $defaultBasePath
} else {
    Write-Host "Default base path ($defaultBasePath) not found."
    $BasePath = Read-Host -Prompt "Enter your projects base path (e.g. C:\Development)"
    if (-not $BasePath -or -not (Test-Path $BasePath)) {
        Write-Error "Base path not found: $BasePath"
        exit 1
    }
}

# Determine full path
if (Test-Path $Project) {
    $folderPath = (Resolve-Path $Project).Path
} elseif (Test-Path "$BasePath\$Project") {
    $folderPath = "$BasePath\$Project"
} else {
    Write-Error "Folder not found: '$Project' (looked in $BasePath\$Project)"
    exit 1
}

# Project name for tab title (folder name only)
$projectName = Split-Path $folderPath -Leaf

# Color-coded profiles per repo — distinct background tints so you can
# visually tell which monolith you're working in at a glance.
# Colors are ARGB hex strings used by Windows Terminal tabColor.
$repoColors = @{
    "PlatformCode"       = "#1a3a5c"   # Deep blue
    "ClientActions"      = "#1a4a3a"   # Teal green
    "MoneyMovement"      = "#4a3a1a"   # Amber/brown
    "Organisation"       = "#3a1a4a"   # Purple
    "ComplianceMonolith" = "#4a1a1a"   # Dark red
    "claude-shared"      = "#1a4a1a"   # Forest green
}
$tabColor = if ($repoColors.ContainsKey($projectName)) { $repoColors[$projectName] } else { "#2d2d2d" }

# Detect Windows Terminal: prefer Preview, fall back to stable
$wtPreview = @{
    Exe      = "$env:LOCALAPPDATA\Microsoft\WindowsApps\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\wt.exe"
    Settings = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json"
}
$wtStable = @{
    Exe      = "$env:LOCALAPPDATA\Microsoft\WindowsApps\Microsoft.WindowsTerminal_8wekyb3d8bbwe\wt.exe"
    Settings = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
}
$terminal = if (Test-Path $wtPreview.Exe) { $wtPreview } elseif (Test-Path $wtStable.Exe) { $wtStable } else { $null }

if (-not $terminal) {
    Write-Error "Windows Terminal not found (tried Preview and Stable)"
    exit 1
}

if ($NoRalph) {
    # Single-pane: Claude Code only — no token, no Ralph profile setup
    & $terminal.Exe --title "$projectName - Claude" --tabColor "$tabColor" -d $folderPath pwsh -NoExit -Command "claude"
} else {
    # Ensure Ralph profile exists in Windows Terminal
    $RalphGuid = "{f1a3b2c4-d5e6-4f78-9a0b-1c2d3e4f5a6b}"
    $ralphCommandline = "`"C:\Program Files\PowerShell\7\pwsh.exe`" -NoExit"

    $settingsPath = $terminal.Settings
    if (Test-Path $settingsPath) {
        $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
        $existing = $settings.profiles.list | Where-Object { $_.guid -eq $RalphGuid }

        if ($existing) {
            if ($existing.commandline -ne $ralphCommandline) {
                $existing.commandline = $ralphCommandline
                Write-Host "Updated Ralph profile"
                $settings | ConvertTo-Json -Depth 20 | Set-Content $settingsPath -Encoding UTF8
            }
        } else {
            $newProfile = [PSCustomObject]@{
                guid        = $RalphGuid
                name        = "Ralph"
                commandline = $ralphCommandline
                hidden      = $false
                icon        = "`u{1F46E}"
            }
            $settings.profiles.list += $newProfile
            Write-Host "Added Ralph profile to Windows Terminal settings"
            $settings | ConvertTo-Json -Depth 20 | Set-Content $settingsPath -Encoding UTF8
        }
    }

    # Launch with 2-pane layout: Left: Claude Code | Right: Ralph (sandbox agent loop)
    # --title sets the tab title to the project name for easy identification
    # --tabColor sets a distinct background tint per repo
    & $terminal.Exe --title "$projectName - Claude" --tabColor "$tabColor" -d $folderPath pwsh -NoExit -Command "claude" `; `
       sp -V -p "Ralph" --title "$projectName - Ralph" -d $folderPath
}
