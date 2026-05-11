#!/usr/bin/env pwsh
#Requires -Version 7.0
# Ralph Wiggum (Sandbox Edition) - Long-running AI agent loop using Claude's Docker sandbox
# Usage: ./ralph-sandbox.ps1 [-MaxIterations 10] [-SkipUpdateCheck] [-LocalImage] [-Prompt "..."] [-TestSonar] [-SelfReview] [-Model sonnet] [-SkipCosmosTests] [-LegacyRecreate] [-NoFreshHome] [-DebugMode]

param(
    [int]$MaxIterations = 10,
    [switch]$SkipUpdateCheck,
    [switch]$LocalImage,
    [string]$Prompt,
    [switch]$TestSonar,
    [switch]$SelfReview,
    [string]$Model = 'sonnet',
    [switch]$SkipCosmosTests,
    [switch]$LegacyRecreate,
    [switch]$NoFreshHome,
    [switch]$ReuseSandbox,
    [switch]$DebugMode
)

# Fresh-HOME mode: each `docker sandbox exec` runs claude with HOME pointed at a
# per-call /tmp dir copied from /home/agent/.claude (auth + config preserved,
# transient state stripped). A2 hypothesis: iter-2+ deadlock is caused by stale
# state under ~/.claude that survives Reset-SandboxState. Default ON when not
# -LegacyRecreate. -NoFreshHome flips it off for differential testing.
$script:UseFreshHome = (-not $LegacyRecreate) -and (-not $NoFreshHome)

$ErrorActionPreference = "Stop"

# Force UTF-8 console output so unicode characters in log lines (e.g. the │ separator)
# render correctly on Windows terminals that default to Windows-1252.
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Preflight: require PowerShell 7+ (runs before anything else, including helper dot-sourcing)
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Red
    Write-Host " ERROR: PowerShell 7+ required" -ForegroundColor Red
    Write-Host "================================================================" -ForegroundColor Red
    Write-Host " Detected: $($PSVersionTable.PSEdition) $($PSVersionTable.PSVersion)" -ForegroundColor Red
    Write-Host " Run this script with 'pwsh', not 'powershell'." -ForegroundColor Red
    Write-Host " Install: https://aka.ms/powershell" -ForegroundColor Red
    Write-Host "================================================================" -ForegroundColor Red
    Write-Host ""
    exit 1
}

$MinimumDockerVersion = '4.62.0'
$AcrRegistry = 'fmfxukcontainerregistry.azurecr.io'
$AcrRegistryName = 'fmfxukcontainerregistry'
$AzureTenantId = 'ef1b2fbe-0adc-4429-b313-23fa5f036456'
$SandboxImage = "$AcrRegistry/ralph-sandbox:latest"
$LocalSandboxImage = 'ralph-sandbox:latest'

$ScriptDir = $PSScriptRoot
. "$PSScriptRoot/ralph-sandbox-helpers.ps1"

$RepoRoot = Find-GitRoot $ScriptDir
$ConfigDir = Join-Path $RepoRoot "tasks\config"
$ImagesDir = Join-Path $RepoRoot "tasks\images"
$WorkingDir = Join-Path $RepoRoot "tasks\current"
foreach ($dir in @($WorkingDir, $ConfigDir, $ImagesDir)) {
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
}

$PrdFile = Join-Path $WorkingDir "prd.json"
$ProgressFile = Join-Path $WorkingDir "progress.txt"
$ArchiveDir = Join-Path (Split-Path $WorkingDir -Parent) "archive"
$LastBranchFile = Join-Path $WorkingDir ".last-branch"
$LogFile = Join-Path $WorkingDir "ralph-sandbox.log"
$McpComposeDir = Join-Path $ScriptDir "mcp"

# Iteration counter surfaced in every Log/Write-StampedLine prefix once the loop starts.
# Empty during setup so those lines don't fake a counter they don't have.
$script:IterationLabel = ''

# Track whether the previous Log/Write-StampedLine output was unstamped, so we can insert
# a single blank line before the next stamped line (visual separator after banners, etc.).
# Doesn't track raw Write-Host or docker stdout — those are on their own.
$script:LastWasUnstamped = $false
$script:LastUnstampedBlank = $false

# Resolve once at startup so we don't re-query the terminal on every Log call.
# Used by Log/Write-StampedLine to insert a blank after wrapped lines for readability.
$script:TerminalWidth = try {
    $w = $Host.UI.RawUI.WindowSize.Width
    if ($w -gt 0) { $w } else { 200 }
} catch { 200 }

# Logging helper - writes to both log file and stdout, prefixing each line with a wall-clock timestamp
# (and current iteration counter, when set). Auto-promotes severity prefixes to color + glyph.
# Pass -NoTimestamp for visual separators (banners, blank lines) where the prefix would be noise.
function Log($Message, [System.ConsoleColor]$ForegroundColor, [switch]$NoTimestamp) {
    if ($NoTimestamp) {
        $output = "$Message"
        $output | Tee-Object -FilePath $LogFile -Append | ForEach-Object {
            if ($ForegroundColor) { Write-Host $_ -ForegroundColor $ForegroundColor } else { Write-Host $_ }
        }
        $script:LastWasUnstamped = $true
        $script:LastUnstampedBlank = ([string]::IsNullOrWhiteSpace($Message))
        return
    }

    # Promote severity-prefixed lines to color + glyph unless the caller already chose a color
    $message = "$Message"
    if (-not $ForegroundColor) {
        if ($message -match '^(\s*)(ERROR|FATAL)\b') {
            $message = $message -replace '^(\s*)(ERROR|FATAL)\b', '$1✗ $2'
            $ForegroundColor = [System.ConsoleColor]::Red
        } elseif ($message -match '^(\s*)WARNING\b') {
            $message = $message -replace '^(\s*)WARNING\b', '$1⚠ WARNING'
            $ForegroundColor = [System.ConsoleColor]::Yellow
        }
    }

    # If we're transitioning out of an unstamped block (banner, etc.) and the last unstamped
    # line wasn't already a blank, prepend a blank line for visual separation.
    if ($script:LastWasUnstamped -and -not $script:LastUnstampedBlank) {
        '' | Tee-Object -FilePath $LogFile -Append | Write-Host
    }
    $script:LastWasUnstamped = $false
    $script:LastUnstampedBlank = $false

    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $iter = if ($script:IterationLabel) { " $script:IterationLabel" } else { '' }
    $lines = $message -split "`r?`n" | ForEach-Object { "[$ts]$iter │ $_" }

    foreach ($line in $lines) {
        Add-Content -Path $LogFile -Value $line
        if ($ForegroundColor) { Write-Host $line -ForegroundColor $ForegroundColor } else { Write-Host $line }
        # If the line was long enough to wrap on the terminal, emit a blank
        # separator so the next stamped line doesn't blur into the wrap.
        if ($line.Length -gt $script:TerminalWidth) {
            Add-Content -Path $LogFile -Value ''
            Write-Host ''
        }
    }
}

# Pre-flight setup
function Setup {

    # Check if claude-shared subtree is out of date
    if (-not $SkipUpdateCheck) {
        Log "Checking claude-shared for updates..."
        Push-Location $RepoRoot
        try {
            git fetch https://github.com/FreemarketFX/claude-shared.git main 2>$null
            $remoteTree = git rev-parse "FETCH_HEAD^{tree}" 2>$null
            $localTree = git rev-parse "HEAD:claude-shared" 2>$null
            if ($remoteTree -and $localTree -and ($remoteTree -ne $localTree)) {
                $currentBranch = git rev-parse --abbrev-ref HEAD
                Log "`nclaude-shared subtree is out of date!" -ForegroundColor Yellow
                Log "Switch to main and run the update script:`n" -ForegroundColor Yellow
                Log "  git checkout main" -ForegroundColor Cyan
                Log "  claude-shared/update-claude-shared.ps1" -ForegroundColor Cyan
                if ($currentBranch -ne "main") {
                    Log "  git checkout $currentBranch`n" -ForegroundColor Cyan
                }
                Log "Or re-run with -SkipUpdateCheck to bypass.`n" -ForegroundColor Yellow
                exit 1
            }
            Log "claude-shared is up to date."
        } finally {
            Pop-Location
        }
    } else {
        Log "Skipping claude-shared update check."
    }

    # Authenticate to Azure and ACR (needed for Key Vault KSM fetch + optional ACR pulls)
    Assert-AzureLogin -TenantId $AzureTenantId -RegistryName $AcrRegistryName

    # Validate docker exists
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Log "ERROR: docker not found in PATH"
        exit 1
    }

    # Check if docker is running
    $dockerCheck = docker info 2>&1
    if ($LASTEXITCODE -ne 0) {
        Log "ERROR: Docker is not running"
        exit 1
    }

    # Check docker version
    $output = docker version --format '{{.Server.Platform.Name}}'
    if ($output -match '(\d+\.\d+\.\d+)') {
        $version = [version]$matches[1]
        if ($version -lt [version]$MinimumDockerVersion) {
            Log "Docker Desktop version $version is too old. Minimum required: $MinimumDockerVersion"
            exit 1
        }
        Log "Docker Desktop version $version is OK."
    } else {
        Log "Could not parse Docker Desktop version from: $output"
        exit 1
    }

    # Confirm the working folder exists
    if (-not (Test-Path $WorkingDir)) {
        Log "Creating working directory: $WorkingDir"
        New-Item -ItemType Directory -Path $WorkingDir -Force | Out-Null
    }
    Log "Working directory OK: $WorkingDir"

    # Archive previous run if branch changed
    if ((Test-Path $PrdFile) -and (Test-Path $LastBranchFile)) {
        $CurrentBranch = Get-BranchName -PrdFile $PrdFile
        $LastBranch = (Get-Content $LastBranchFile -Raw -ErrorAction SilentlyContinue)
        if ($LastBranch) { $LastBranch = $LastBranch.Trim() }

        if ($CurrentBranch -and $LastBranch -and ($CurrentBranch -ne $LastBranch)) {
            $Date = Get-Date -Format "yyyy-MM-dd"
            $FolderName = $LastBranch -replace "^ralph/", ""
            $ArchiveFolder = Join-Path $ArchiveDir "$Date-$FolderName"

            Log "Archiving previous run: $LastBranch"
            New-Item -ItemType Directory -Path $ArchiveFolder -Force | Out-Null

            if (Test-Path $PrdFile) { Copy-Item $PrdFile $ArchiveFolder }
            if (Test-Path $ProgressFile) { Copy-Item $ProgressFile $ArchiveFolder }
            Log "   Archived to: $ArchiveFolder"

            @("# Ralph Progress Log", "Started: $(Get-Date)", "---") | Set-Content $ProgressFile
        }
    }

    # Track current branch
    if (Test-Path $PrdFile) {
        $CurrentBranch = Get-BranchName -PrdFile $PrdFile
        if ($CurrentBranch) {
            [System.IO.File]::WriteAllText($LastBranchFile, $CurrentBranch)
        }
    }

    # Initialize progress file if it doesn't exist
    if (-not (Test-Path $ProgressFile)) {
        New-Item -ItemType Directory -Path $WorkingDir -Force | Out-Null
        @("# Ralph Progress Log", "Started: $(Get-Date)", "---") | Set-Content $ProgressFile
    }

    # Ensure working directory artifacts are gitignored at repo root
    $gitignore = Join-Path $RepoRoot ".gitignore"
    $relativeDir = [System.IO.Path]::GetRelativePath($RepoRoot, $WorkingDir) -replace '\\', '/'
    $relativeImagesDir = [System.IO.Path]::GetRelativePath($RepoRoot, $ImagesDir) -replace '\\', '/'
    $ignorePatterns = @("$relativeDir/*.log", "$relativeDir/.last-branch", "$relativeDir/.iteration-output", ".claude/settings.local.json*", "$relativeImagesDir/**", "**/keeper.ini", ".git.windows-original")
    $repoName = Split-Path $RepoRoot -Leaf
    if ($repoName -ne "claude-shared") {
        $ignorePatterns += ".mcp.json"
    }
    foreach ($pattern in $ignorePatterns) {
        $escaped = [regex]::Escape($pattern)
        if (-not (Test-Path $gitignore) -or -not (Select-String -Path $gitignore -Pattern "^$escaped$" -Quiet)) {
            Add-Content -Path $gitignore -Value $pattern
            Log "Added $pattern to $gitignore"
        }
    }

    # Sync settings.local.json to .claude/ in the repo root
    $settingsSource = Join-Path $ScriptDir "settings.local.json"
    $settingsTarget = Join-Path $RepoRoot ".claude/settings.local.json"
    if (Test-Path $settingsSource) {
        if (Test-Path $settingsTarget) {
            $sourceHash = (Get-FileHash $settingsSource -Algorithm SHA256).Hash
            $targetHash = (Get-FileHash $settingsTarget -Algorithm SHA256).Hash
            if ($sourceHash -eq $targetHash) {
                Log "settings.local.json is up to date, no copy needed."
            } else {
                $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
                $backupPath = "$settingsTarget.backup-$timestamp"
                Rename-Item $settingsTarget $backupPath
                Log "Backup created: $(Split-Path $backupPath -Leaf)"
                Copy-Item $settingsSource $settingsTarget
                Log "settings.local.json updated."
            }
        } else {
            New-Item -ItemType Directory -Path (Split-Path $settingsTarget) -Force | Out-Null
            Copy-Item $settingsSource $settingsTarget
            Log "settings.local.json copied to .claude/"
        }
    }

    # Archive previous log for post-run analysis
    if (Test-Path $LogFile) {
        $prevLog = $LogFile -replace '\.log$', '.prev.log'
        Copy-Item $LogFile $prevLog -Force
    }
}

# Run setup routine
Setup

# Start fresh log each run
"Ralph Sandbox started: $(Get-Date)" | Set-Content $LogFile

Log "Starting Ralph (Sandbox Edition) - Max iterations: $MaxIterations"
Log "Repo root: $RepoRoot"
Log "Log file: $LogFile"
Log ("Fresh-HOME mode: {0}" -f ($(if ($script:UseFreshHome) { 'ON (per-call $HOME copied from ~/.claude minus state subdirs)' } else { 'OFF' })))

# When -SkipCosmosTests is set, the loop skips tests that need a Cosmos emulator and
# delegates that coverage to the user's local pre-push hook. If no pre-push hook exists,
# that delegation is silently void — warn so the user can install one before pushing.
# Resolve via `git rev-parse --git-path` so worktrees (where $RepoRoot/.git is a file
# pointing at the main repo's hooks dir) report the correct hook path.
if ($SkipCosmosTests) {
    Push-Location $RepoRoot
    try {
        $prePushHook = (git rev-parse --git-path hooks/pre-push 2>$null)
        if ($prePushHook) { $prePushHook = $prePushHook.Trim() }
    } finally { Pop-Location }
    if (-not $prePushHook -or -not (Test-Path $prePushHook)) {
        Log "WARNING: -SkipCosmosTests set but no pre-push hook found (looked at: $prePushHook)."
        Log "WARNING: Cosmos test coverage is supposed to run via the pre-push gate. Install one before pushing, or full-suite verify locally."
    }
}

$McpManifest = Join-Path $ConfigDir "mcp-servers.yml"

# Pull the latest sandbox image from ACR (skip when using a local build).
# We always recreate the sandbox below regardless of whether the image changed, so we no
# longer branch on the return — the function still runs for its side-effects (pull + retag).
if (-not $LocalImage) {
    Log "Checking for sandbox image updates..."
    Ensure-LatestSandboxImage -ImageRef $SandboxImage -LocalTag $LocalSandboxImage
} else {
    Log "Skipping ACR image pull — using local ralph-sandbox:latest."
}

# Sync proxy-config.json before sandbox creation so deny-by-default policy is active from start.
# Side-effect call; return value (whether the file changed) is no longer consulted because
# we always recreate the sandbox.
Sync-ProxyConfig -ScriptDir $ScriptDir | Out-Null

# Build mount args once — reused for initial creation and mid-loop recovery
$sandboxName = "claude-$((Get-Item $RepoRoot).Name)"
$script:sandboxMountArgs = Build-SandboxMountArgs -RepoRoot $RepoRoot

# Always remove any pre-existing sandbox at startup so we begin with a clean VM.
# Previous design reused a "running and current" sandbox to save ~10s of startup time, but
# that left orphan claude/dotnet processes alive when the host script died (Ctrl+C, closed
# terminal tab, host crash). The next run would silently inherit a polluted sandbox where
# the new claude competes with the orphan for the workspace, producing the symptom of a
# silent/stalled iteration. Recreating unconditionally trades a few seconds for guaranteed
# isolation between runs.
$sandboxLine = Measure-Step -Name "initial.sandbox-ls" -Body {
    $list = docker sandbox ls 2>&1
    $list | Where-Object { $_ -match "^\s*$([regex]::Escape($sandboxName))\s+" }
}
$script:ReuseExistingSandbox = $false
if ($sandboxLine) {
    if ($ReuseSandbox) {
        Log "Sandbox '$sandboxName' already exists and -ReuseSandbox set — keeping it."
        $script:ReuseExistingSandbox = $true
    } else {
        Log "Sandbox '$sandboxName' already exists — removing for a clean start..."
        Measure-Step -Name "initial.sandbox-rm" -Body {
            docker sandbox rm $sandboxName 2>&1 | ForEach-Object { if ($_) { Log $_ } }
            if ($LASTEXITCODE -ne 0) {
                Log "ERROR: Failed to remove pre-existing sandbox"
                exit 1
            }
        }
    }
}
# MCP Manifest: Docker image caching & .mcp.json generation ---
if (Test-Path $McpManifest) {

    if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
        Log "Installing powershell-yaml module..."
        Install-Module -Name powershell-yaml -Force -Scope CurrentUser
    }
    Import-Module powershell-yaml

    $manifest = ConvertFrom-Yaml (Get-Content $McpManifest -Raw)

    # Pull and cache Docker images from compose files
    $requiredTars = @()
    foreach ($name in $manifest.servers.Keys) {
        $server = $manifest.servers[$name]
        if ($server.docker -and $server.docker.compose) {
            $composeFile = Join-Path $McpComposeDir $server.docker.compose
            if (-not (Test-Path $composeFile)) {
                Log "ERROR: Compose file not found: $composeFile"
                exit 1
            }

            # Parse compose YAML to extract image names
            $composeYaml = ConvertFrom-Yaml (Get-Content $composeFile -Raw)
            $images = @()
            foreach ($svcName in $composeYaml.services.Keys) {
                $svc = $composeYaml.services[$svcName]
                if ($svc.image -and $images -notcontains $svc.image) {
                    $images += $svc.image
                }
            }

            # Pull and cache each unique image
            foreach ($image in $images) {
                $requiredTars += ConvertTo-SafeImageFilename $image
                $tarFile = Join-Path $ImagesDir (ConvertTo-SafeImageFilename $image)
                Log "Pulling Docker image: $image"
                $pullOutput = docker pull $image 2>&1
                $pullOutput | ForEach-Object { Log $_ }
                $pullOutput = $pullOutput | Out-String
                if ($LASTEXITCODE -ne 0) {
                    Log "ERROR: Failed to pull $image"
                    exit 1
                }
                $imageUpdated = $pullOutput -notmatch "Image is up to date"
                if (-not (Test-Path $tarFile) -or $imageUpdated) {
                    Log "Saving image to: $tarFile"
                    docker save $image -o $tarFile
                    if ($LASTEXITCODE -ne 0) {
                        Log "ERROR: Failed to save $image"
                        exit 1
                    }
                } else {
                    Log "Image $image unchanged and tar exists — skipping save"
                }
            }
        }
    }

    # Remove stale image tars not referenced by any compose file
    Get-ChildItem -Path $ImagesDir -Filter "*.tar" | Where-Object {
        $requiredTars -notcontains $_.Name
    } | ForEach-Object {
        Log "Removing stale image tar: $($_.Name)"
        Remove-Item $_.FullName -Force
    }

    # Generate .mcp.json for Claude Code
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
    $mcpJsonPath = Join-Path $RepoRoot ".mcp.json"
    Set-Content -Path $mcpJsonPath -Value $mcpJson -Encoding UTF8 -Force
    Log "Generated $mcpJsonPath"
} else {
    Log "No MCP manifest found at $McpManifest — skipping"
    $mcpJsonPath = Join-Path $RepoRoot ".mcp.json"
    if (Test-Path $mcpJsonPath) {
        Remove-Item $mcpJsonPath -Force
        Log "Removed stale $mcpJsonPath"
    }
}

try {
    $KeeperFile = Measure-Step -Name "initial.keeper-write" -Body { Write-KeeperFile }
} catch {
    Log "ERROR: $_"
    exit 1
}

# Restore .git file if a previous sandbox crashed before teardown
$gitBackup = Join-Path $RepoRoot ".git.windows-original"
if (Test-Path $gitBackup) {
    Copy-Item $gitBackup (Join-Path $RepoRoot ".git") -Force
    Remove-Item $gitBackup -Force
    Log "Restored .git from backup (previous sandbox may have crashed)"
}

if ($script:ReuseExistingSandbox) {
    Log "Reusing existing sandbox '$sandboxName' — skipping create."
    if ($KeeperFile -and (Test-Path $KeeperFile)) {
        Remove-Item -Path $KeeperFile -Force
        Log ".keeper cleaned up from host"
    }
} else {
    Log "Creating sandbox '$sandboxName' with template..."
    $initialCreateSw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        Measure-Step -Name "initial.sandbox-create" -Body {
            $createSw = [System.Diagnostics.Stopwatch]::StartNew()
            docker sandbox create --name $sandboxName --template $LocalSandboxImage claude $script:sandboxMountArgs 2>&1 | ForEach-Object {
                if ($_) { Log ("[+{0,6:N1}s] {1}" -f $createSw.Elapsed.TotalSeconds, $_) }
            }
            if ($LASTEXITCODE -ne 0) {
                Log "ERROR: Failed to create sandbox"
                exit 1
            }
        }
    } finally {
        if ($KeeperFile -and (Test-Path $KeeperFile)) {
            Remove-Item -Path $KeeperFile -Force
            Log ".keeper cleaned up from host"
        }
    }
    $initialCreateSw.Stop()
    Log ("Initial sandbox create total: {0:N1}s" -f $initialCreateSw.Elapsed.TotalSeconds)
}

$noProgressCount = 0
$lastCommitHash = $null
$killRetries = 0
$MaxKillRetries = 3

for ($i = 1; $i -le $MaxIterations; $i++) {
    $script:IterationLabel = "[$i/$MaxIterations]"
    Log "" -NoTimestamp
    Log "" -NoTimestamp
    Log "===============================================================" -NoTimestamp
    Log "  Ralph Iteration $i of $MaxIterations (Sandbox)" -NoTimestamp
    Log "===============================================================" -NoTimestamp
    Log "" -NoTimestamp
    Log "" -NoTimestamp

    # Between iterations: by default reset state in-place (~1-3s, keeps /tmp/build warm)
    # because Invoke-SandboxRun now uses `docker sandbox exec` which is reusable.
    # -LegacyRecreate flips back to the historical full rm+create cycle (~297s) — use
    # if exec turns out to have its own state-corruption issue we haven't identified.
    # First iteration always uses Ensure-SandboxRunning since the sandbox was just created.
    try {
        if ($i -gt 1) {
            Cycle-Sandbox -SandboxName $sandboxName -TemplateName $LocalSandboxImage -MountArgs $script:sandboxMountArgs -Legacy:$LegacyRecreate
        } else {
            Ensure-SandboxRunning -SandboxName $sandboxName -TemplateName $LocalSandboxImage -MountArgs $script:sandboxMountArgs
        }
        if ($DebugMode) {
            Capture-SandboxDiagnostics -SandboxName $sandboxName -Label "iter${i}-pre-claude"
        }
    } catch {
        Log "ERROR: $_"
        exit 1
    }

    # Get the repo root as it appears inside the sandbox
    $linuxWorkspacePath = ($RepoRoot -replace '\\','/') -replace '^([A-Za-z]):',{ '/' + $_.Groups[1].Value.ToLower() }

    # Clean line-ending noise from killed iterations before each run (timeout to avoid hanging on dead VM)
    try {
        $execJob = Start-Job -ScriptBlock {
            docker sandbox exec $using:sandboxName bash -c "cd '$using:linuxWorkspacePath' && git checkout HEAD -- tasks/ 2>/dev/null || true" 2>&1
        }
        $completed = $execJob | Wait-Job -Timeout 30
        if ($completed) {
            Receive-Job $execJob | ForEach-Object { if ($_) { Log $_ } }
        } else {
            Stop-Job $execJob -ErrorAction SilentlyContinue
            Log "WARNING: git checkout exec timed out — sandbox may be unresponsive"
        }
        Remove-Job $execJob -Force -ErrorAction SilentlyContinue
    } catch { }

    $claudeMdPath = "$($linuxWorkspacePath -replace '/claude-shared','')/claude-shared/ralph-sandbox/CLAUDE.md"
    $iterationPrompt = if ($Prompt) { $Prompt } else { "Read $claudeMdPath and follow its instructions exactly." }

    # Prepend MCP startup gate when Docker-based MCP servers are configured (iteration 1 only)
    $McpStartupPrompt = Join-Path $McpComposeDir "mcp-startup-prompt.md"
    if (($i -eq 1) -and (Test-Path $McpManifest) -and (Test-Path $McpStartupPrompt)) {
        $startupContent = Get-Content $McpStartupPrompt -Raw
        $iterationPrompt = $startupContent + "`n`n" + $iterationPrompt
    }

    # When -SkipCosmosTests is set, instruct claude to bypass tests that depend on the
    # Cosmos emulator (unavailable in the sandbox image). The user's local pre-push git
    # hook runs the full suite before any push, so coverage is preserved.
    if ($SkipCosmosTests) {
        $cosmosSkipPrompt = @"
SANDBOX TEST CONSTRAINT: The Cosmos DB emulator is unavailable in this sandbox image (too large to bundle).
Do NOT attempt to run tests that require a Cosmos emulator at localhost:8081 — typically tests using a shared Cosmos test fixture or collection. They will hang or fail with connection-refused.

Identify the Cosmos-bound tests by inspecting the test project's fixtures and collections (look for whatever the repo uses to provide a Cosmos client). Use the dotnet test --filter expression to exclude them, or run only pure-unit specs that have no shared fixture dependency.

If the only meaningful coverage for a story sits in a Cosmos-bound test, mark it verified by inspection in progress.txt and note "Cosmos tests deferred to local pre-push hook" — do not block the iteration on it. The user's git pre-push hook runs the full suite (with the emulator available) before any push, so the gap is covered before the change leaves the machine.

"@
        $iterationPrompt = $cosmosSkipPrompt + $iterationPrompt
    }

    $IterationOutput = Join-Path $WorkingDir ".iteration-output"

    # Per-call fresh HOME dir (A2): claude runs in a clean state dir copied from
    # ~/.claude minus transient subdirs, isolating it from any cross-iter pollution.
    $freshHome = if ($script:UseFreshHome) { "/tmp/claude-home-iter${i}-$(Get-Random)" } else { '' }

    # Stream Claude output: raw JSON goes to log + temp file, parsed summary to stdout.
    "" | Set-Content $IterationOutput
    Invoke-SandboxRun -SandboxName $sandboxName -WorkDir $linuxWorkspacePath -Prompt $iterationPrompt -LogFile $LogFile -IterationOutput $IterationOutput -Model $Model -FreshHomeDir $freshHome -DebugMode:$DebugMode

    # Check for completion signal - only in the final "result" line, not in tool_result
    # file contents (which echo the CLAUDE.md instructions containing the tag)
    $resultLines = Get-Content $IterationOutput -ErrorAction SilentlyContinue |
        Where-Object { $_ -match '"type":"result"' }

    # Detect auth failures — abort immediately, no point retrying with an expired key
    # Only check result/error lines (not full output) to avoid false positives from
    # agent editing code that contains "authentication_error" string literals
    $authFail = Get-Content $IterationOutput -ErrorAction SilentlyContinue |
        Where-Object { $_ -match '"type":"result"' -or $_ -match '"error":"authentication_failed"' } |
        Where-Object { $_ -match '"authentication_error"' -or $_ -match '"authentication_failed"' }
    if ($authFail) {
        Log "Authentication failed — API key may have expired. Aborting loop."
        Remove-Item $IterationOutput -ErrorAction SilentlyContinue
        $repoName = Split-Path $RepoRoot -Leaf
        Show-Toast "Ralph Auth Failed ($repoName)" "API key expired — loop aborted"
        exit 1
    }

    # Detect killed iterations (OOM/exit 137) — no result line means the process was killed
    if (-not $resultLines) {
        $killedIter = $i
        $killRetries++
        Log "Iteration $killedIter appears to have been killed (no result received). Auto-recovering ($killRetries/$MaxKillRetries)..."

        # Bail out if kills are persistent across iterations — counter resets only when an
        # iteration produces a result, so $MaxKillRetries consecutive kills (across any
        # iteration indices, with no successes between) means the loop isn't recovering.
        if ($killRetries -ge $MaxKillRetries) {
            Log "Hit $MaxKillRetries consecutive killed iterations (last: $killedIter) — aborting loop."
            Add-Content -Path $ProgressFile -Value "`n## $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $MaxKillRetries consecutive iterations KILLED (last: $killedIter) — loop aborted"
            Remove-Item $IterationOutput -ErrorAction SilentlyContinue
            $repoName = Split-Path $RepoRoot -Leaf
            Show-Toast "Ralph Aborted ($repoName)" "$MaxKillRetries consecutive iterations killed (last: $killedIter) — giving up"
            exit 1
        }

        # Kill orphan claude/node/dotnet first — a killed iteration leaves the
        # in-sandbox claude process alive even though the host docker exec died,
        # and a retry exec will hang competing with the orphan. This is the same
        # cleanup Reset-SandboxState does between iterations; we need it here too
        # because the retry path doesn't go through Cycle-Sandbox.
        if (-not $LegacyRecreate) {
            Reset-SandboxState -SandboxName $sandboxName
        }

        # Auto-stash uncommitted changes inside the sandbox.
        # Use --workdir so we don't have to `cd` into a path that might contain shell
        # metacharacters, and pass the iter# via --env so the stash message can't be
        # broken out of either. Previously this used `cd "$(git rev-parse --show-toplevel)"`
        # which silently no-op'd because the sandbox's default cwd isn't a git repo.
        try {
            Log "Auto-stash:"
            docker sandbox exec --workdir $linuxWorkspacePath --env "RALPH_KILLED_ITER=$killedIter" $sandboxName bash -c 'git stash --include-untracked -m "ralph: auto-stash after killed iteration $RALPH_KILLED_ITER"' 2>&1 | ForEach-Object { if ($_) { Log "  $_" } }
        } catch {
            Log "Warning: Failed to auto-stash: $_"
        }

        # Log kill to progress.txt
        $killEntry = "## $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Iteration $killedIter KILLED (no result received) — auto-stashed and retrying ($killRetries/$MaxKillRetries)"
        Add-Content -Path $ProgressFile -Value "`n$killEntry"

        # Retry this iteration
        $i--
        Remove-Item $IterationOutput -ErrorAction SilentlyContinue
        $repoName = Split-Path $RepoRoot -Leaf
        Show-Toast "Ralph Iteration $killedIter Killed ($repoName)" "Iteration killed (OOM?) — retrying ($killRetries/$MaxKillRetries)"
        Start-Sleep -Seconds 2
        continue
    }

    # Iteration produced a result — reset the kill retry counter
    $killRetries = 0

    if (($resultLines | Out-String) -match '<promise>COMPLETE</promise>') {
        # Agent should only emit COMPLETE when every story has passes:true.
        # Verify against prd.json before honoring it — sonnet has been observed
        # emitting COMPLETE prematurely after only one story.
        $unfinishedStories = @()
        if (Test-Path $PrdFile) {
            try {
                $prd = Get-Content $PrdFile -Raw | ConvertFrom-Json
                $unfinishedStories = @($prd.userStories | Where-Object { -not $_.passes } | ForEach-Object { $_.id })
            } catch {
                Log "Warning: unable to parse $PrdFile to verify COMPLETE signal: $_"
            }
        }

        if ($unfinishedStories.Count -gt 0) {
            Log ""
            Log "WARNING: agent emitted <promise>COMPLETE</promise> but $($unfinishedStories.Count) story(ies) still have passes:false: $($unfinishedStories -join ', ')."
            Log "Ignoring premature completion signal - continuing the loop."
            Remove-Item $IterationOutput -ErrorAction SilentlyContinue
            $repoName = Split-Path $RepoRoot -Leaf
            Show-Toast "Ralph Iteration $i ($repoName)" "Premature COMPLETE ignored - $($unfinishedStories.Count) stories remain"
            Start-Sleep -Seconds 2
            continue
        }

        Log ""
        Log "Ralph completed all tasks!"
        Log "Completed at iteration $i of $MaxIterations"
        Remove-Item $IterationOutput -ErrorAction SilentlyContinue

        # Quality gates — run optional review skills then re-loop Ralph
        if ($TestSonar) {
            Log ""
            Log "Running /test-sonar quality gate..."
            Cycle-Sandbox -SandboxName $sandboxName -TemplateName $LocalSandboxImage -MountArgs $script:sandboxMountArgs -Legacy:$LegacyRecreate
            $TestSonarPrompt = "run /test-sonar full audit against the changes. Update the prd with any necessary fixes"
            $sonarHome = if ($script:UseFreshHome) { "/tmp/claude-home-sonar-$(Get-Random)" } else { '' }
            Invoke-SandboxRun -SandboxName $sandboxName -WorkDir $linuxWorkspacePath -Prompt $TestSonarPrompt -LogFile $LogFile -Model 'opus' -FreshHomeDir $sonarHome -StagnationSeconds 1800 -DebugMode:$DebugMode

            Log "Re-running Ralph loop after test-sonar..."
            Cycle-Sandbox -SandboxName $sandboxName -TemplateName $LocalSandboxImage -MountArgs $script:sandboxMountArgs -Legacy:$LegacyRecreate
            $postSonarHome = if ($script:UseFreshHome) { "/tmp/claude-home-postsonar-$(Get-Random)" } else { '' }
            Invoke-SandboxRun -SandboxName $sandboxName -WorkDir $linuxWorkspacePath -Prompt $iterationPrompt -LogFile $LogFile -Model $Model -FreshHomeDir $postSonarHome -DebugMode:$DebugMode
        }

        if ($SelfReview) {
            Log ""
            Log "Running /self-code-review quality gate..."
            Cycle-Sandbox -SandboxName $sandboxName -TemplateName $LocalSandboxImage -MountArgs $script:sandboxMountArgs -Legacy:$LegacyRecreate
            $SelfReviewPrompt = "run /self-code-review against these changes. Update the prd with any necessary changes"
            $reviewHome = if ($script:UseFreshHome) { "/tmp/claude-home-review-$(Get-Random)" } else { '' }
            Invoke-SandboxRun -SandboxName $sandboxName -WorkDir $linuxWorkspacePath -Prompt $SelfReviewPrompt -LogFile $LogFile -Model 'opus' -FreshHomeDir $reviewHome -StagnationSeconds 1800 -DebugMode:$DebugMode

            Log "Re-running Ralph loop after self-review..."
            Cycle-Sandbox -SandboxName $sandboxName -TemplateName $LocalSandboxImage -MountArgs $script:sandboxMountArgs -Legacy:$LegacyRecreate
            $postReviewHome = if ($script:UseFreshHome) { "/tmp/claude-home-postreview-$(Get-Random)" } else { '' }
            Invoke-SandboxRun -SandboxName $sandboxName -WorkDir $linuxWorkspacePath -Prompt $iterationPrompt -LogFile $LogFile -Model $Model -FreshHomeDir $postReviewHome -DebugMode:$DebugMode
        }

        # Run post-ralph skill inside the sandbox to archive and commit
        Log ""
        Log "Running post-ralph skill to archive completed run..."
        Cycle-Sandbox -SandboxName $sandboxName -TemplateName $LocalSandboxImage -MountArgs $script:sandboxMountArgs -Legacy:$LegacyRecreate
        $PostRalphPrompt = "Run /post-ralph to archive the completed Ralph run"
        $postRalphHome = if ($script:UseFreshHome) { "/tmp/claude-home-postralph-$(Get-Random)" } else { '' }
        Invoke-SandboxRun -SandboxName $sandboxName -WorkDir $linuxWorkspacePath -Prompt $PostRalphPrompt -LogFile $LogFile -Model $Model -FreshHomeDir $postRalphHome -DebugMode:$DebugMode

        $repoName = Split-Path $RepoRoot -Leaf
        Show-Toast "Ralph Complete ($repoName)" "All tasks done at iteration $i of $MaxIterations"
        exit 0
    }
    Remove-Item $IterationOutput -ErrorAction SilentlyContinue

    # Track progress — abort if agent is stuck (no new commits for 3 consecutive iterations)
    $currentHash = $null
    try {
        $currentHash = (docker sandbox exec $sandboxName bash -c 'git rev-parse HEAD 2>/dev/null' 2>&1).Trim()
    } catch { }

    if ($currentHash -and $currentHash -eq $lastCommitHash) {
        $noProgressCount++
        Log "No new commits this iteration ($noProgressCount consecutive)"
    } else {
        $noProgressCount = 0
        $lastCommitHash = $currentHash
    }

    if ($noProgressCount -ge 3) {
        Log "No progress for 3 consecutive iterations — agent appears stuck. Aborting."
        $repoName = Split-Path $RepoRoot -Leaf
        Show-Toast "Ralph Stuck ($repoName)" "No commits for 3 iterations — aborting"
        exit 1
    }

    Log "Iteration $i complete. Continuing..."
    $repoName = Split-Path $RepoRoot -Leaf
    Show-Toast "Ralph Iteration $i ($repoName)" "Iteration $i of $MaxIterations complete"
    Start-Sleep -Seconds 2
}

Log ""
Log "Ralph reached max iterations ($MaxIterations) without completing all tasks."
Log "Check $ProgressFile for status."
$repoName = Split-Path $RepoRoot -Leaf
Show-Toast "Ralph Stopped ($repoName)" "Reached max iterations ($MaxIterations) without completing"
exit 1
