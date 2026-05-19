# ralph-sandbox-helpers.ps1 — Self-contained helper functions for ralph-sandbox.ps1

# Run $Body, log start + duration. Returns whatever $Body returns.
# Used to break the opaque "create took 5min" log into per-step costs.
function Measure-Step {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Body
    )
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Log "[step] $Name : starting"
    try {
        return & $Body
    } finally {
        $sw.Stop()
        Log ("[step] {0} : done in {1:N1}s" -f $Name, $sw.Elapsed.TotalSeconds)
    }
}

# Build the mount arguments array for sandbox creation.
# Hoisted to a function so the same args can be reused when recreating a dead sandbox.
function Build-SandboxMountArgs {
    param([Parameter(Mandatory)][string]$RepoRoot)

    $canonicalRoot = (Resolve-Path (Get-MainRepoRoot -RepoRoot $RepoRoot)).Path
    $PlatformCode = Resolve-SiblingRepo -RepoRoot $RepoRoot -Name "PlatformCode"
    $Main = Resolve-SiblingRepo -RepoRoot $RepoRoot -Name "Main"

    $mountArgs = @($RepoRoot, "$($env:USERPROFILE)\.claude:readonly")

    # Mount main repo .git dir so git works inside worktree sandboxes
    $isWorktree = ($canonicalRoot -ne (Resolve-Path $RepoRoot).Path)
    if ($isWorktree) {
        $mainGitDir = Join-Path $canonicalRoot ".git"
        if (Test-Path $mainGitDir) {
            $mountArgs += $mainGitDir
            Log "Worktree detected — mounting main .git (read-write): $mainGitDir"
        } else {
            Log "WARNING: main .git dir not found at $mainGitDir — worktree git ops may fail in sandbox"
        }
    }

    if ($PlatformCode -and $PlatformCode -ne $canonicalRoot) {
        $mountArgs += "${PlatformCode}:readonly"
    } elseif ($PlatformCode) {
        Log "RepoRoot is PlatformCode — skipping duplicate readonly mount"
    } else {
        Log "WARNING: PlatformCode not found as sibling repo — skipping mount"
    }
    if ($Main -and $Main -ne $canonicalRoot) {
        $mountArgs += "${Main}:readonly"
    } elseif ($Main) {
        Log "RepoRoot is Main — skipping duplicate readonly mount"
    } else {
        Log "WARNING: Main not found as sibling repo — skipping mount"
    }
    return ,$mountArgs
}

# Fetch KSM config from Azure Key Vault and write .keeper so `docker sandbox create`
# can import the secret. Returns the .keeper path so the caller can clean up post-create.
function Write-KeeperFile {
    Log "Fetching KSM config from Key Vault..."
    $KsmConfig = az keyvault secret show `
        --vault-name fmfxukdevinfrakv `
        --name claude-docker-sandbox-ksm-config `
        --query value -o tsv
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to fetch KSM config from Key Vault"
    }
    $KeeperDir = Join-Path $env:USERPROFILE '.claude'
    $KeeperFile = Join-Path $KeeperDir '.keeper'
    if (-not (Test-Path $KeeperDir)) { New-Item -ItemType Directory -Path $KeeperDir -Force | Out-Null }
    Set-Content -Path $KeeperFile -Value $KsmConfig -NoNewline
    Log "KSM config written to $KeeperFile"
    return $KeeperFile
}

# Check if a sandbox exists and is running. If it disappeared (OOM, Docker restart),
# recreate it — including re-importing the KSM secret — so the iteration loop can
# continue instead of failing repeatedly.
function Ensure-SandboxRunning {
    param(
        [Parameter(Mandatory)][string]$SandboxName,
        [Parameter(Mandatory)][string]$TemplateName,
        [Parameter(Mandatory)][array]$MountArgs
    )

    $sandboxList = docker sandbox ls 2>&1
    $sandboxLine = $sandboxList | Where-Object { $_ -match "^\s*$([regex]::Escape($SandboxName))\s+" }

    if ($sandboxLine -and ($sandboxLine -match '\brunning\b')) {
        # Sandbox claims to be running — verify with a liveness probe
        try {
            $probeResult = $null
            $probeJob = Start-Job -ScriptBlock { docker sandbox exec $using:SandboxName echo ok 2>&1 }
            $completed = $probeJob | Wait-Job -Timeout 15
            if ($completed) {
                $probeResult = Receive-Job $probeJob
            }
            Remove-Job $probeJob -Force -ErrorAction SilentlyContinue
            if ($probeResult -match 'ok') {
                return
            }
            Log "Sandbox '$SandboxName' is unresponsive — removing and recreating..."
        } catch {
            Log "Sandbox '$SandboxName' liveness probe failed: $_ — recreating..."
        }
        docker sandbox rm $SandboxName 2>&1 | ForEach-Object { if ($_) { Log $_ } }
    } elseif ($sandboxLine) {
        Log "Sandbox '$SandboxName' is not running (status: $sandboxLine). Removing before recreate..."
        docker sandbox rm $SandboxName 2>&1 | ForEach-Object { if ($_) { Log $_ } }
    }

    Log "Recreating sandbox '$SandboxName'..."
    $totalSw = [System.Diagnostics.Stopwatch]::StartNew()
    $keeperFile = Measure-Step -Name "ensure.keeper-write" -Body { Write-KeeperFile }
    try {
        Measure-Step -Name "ensure.sandbox-create" -Body {
            $createSw = [System.Diagnostics.Stopwatch]::StartNew()
            docker sandbox create --name $SandboxName --template $TemplateName claude $MountArgs 2>&1 | ForEach-Object {
                if ($_) { Log ("[+{0,6:N1}s] {1}" -f $createSw.Elapsed.TotalSeconds, $_) }
            }
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to recreate sandbox '$SandboxName'"
            }
        }
    } finally {
        if ($keeperFile -and (Test-Path $keeperFile)) {
            Remove-Item -Path $keeperFile -Force
            Log ".keeper cleaned up from host"
        }
    }
    $totalSw.Stop()
    Log ("Sandbox '$SandboxName' recreated successfully in {0:N1}s." -f $totalSw.Elapsed.TotalSeconds)
}

# Force-recreate a running sandbox. Required because `docker sandbox run` hangs
# on the second invocation against the same running sandbox (Docker sandbox bug).
function Recreate-Sandbox {
    param(
        [Parameter(Mandatory)][string]$SandboxName,
        [Parameter(Mandatory)][string]$TemplateName,
        [Parameter(Mandatory)][array]$MountArgs
    )

    Log "Recreating sandbox '$SandboxName' (workaround for second-run stall)..."
    $totalSw = [System.Diagnostics.Stopwatch]::StartNew()

    $sandboxLine = Measure-Step -Name "recreate.sandbox-ls" -Body {
        $list = docker sandbox ls 2>&1
        $list | Where-Object { $_ -match "^\s*$([regex]::Escape($SandboxName))\s+" }
    }
    if ($sandboxLine) {
        Measure-Step -Name "recreate.sandbox-rm" -Body {
            docker sandbox rm $SandboxName 2>&1 | ForEach-Object { if ($_) { Log $_ } }
        }
    }

    $keeperFile = Measure-Step -Name "recreate.keeper-write" -Body { Write-KeeperFile }
    try {
        Measure-Step -Name "recreate.sandbox-create" -Body {
            $createSw = [System.Diagnostics.Stopwatch]::StartNew()
            docker sandbox create --name $SandboxName --template $TemplateName claude $MountArgs 2>&1 | ForEach-Object {
                if ($_) { Log ("[+{0,6:N1}s] {1}" -f $createSw.Elapsed.TotalSeconds, $_) }
            }
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to recreate sandbox '$SandboxName'"
            }
        }
    } finally {
        if ($keeperFile -and (Test-Path $keeperFile)) {
            Remove-Item -Path $keeperFile -Force
            Log ".keeper cleaned up from host"
        }
    }
    $totalSw.Stop()
    Log ("Sandbox '$SandboxName' recreated successfully in {0:N1}s." -f $totalSw.Elapsed.TotalSeconds)
}

function Get-BranchName {
    param(
        [Parameter(Mandatory)][string]$PrdFile
    )

    try {
        $prd = Get-Content $PrdFile -Raw | ConvertFrom-Json
        return $prd.branchName
    } catch {
        return $null
    }
}

function Find-GitRoot ($Dir) {
    $Dir = (Get-Location).Path
    while ($Dir) {
        if (Test-Path (Join-Path $Dir '.git')) {
            return $Dir
        }
        $parent = Split-Path $Dir -Parent
        if ($parent -eq $Dir) { break }  # at root
        $Dir = $parent
    }
    Write-Warning "No git repository found."
}

# Toast notification helper — shells out to Windows PowerShell 5.1 for WinRT access
function Show-Toast($Title, $Message) {
    try {
        $safeTitle = [System.Security.SecurityElement]::Escape($Title)
        $safeMessage = [System.Security.SecurityElement]::Escape($Message)
        $script = @"
[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
[Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom, ContentType = WindowsRuntime] | Out-Null
`$xml = New-Object Windows.Data.Xml.Dom.XmlDocument
`$xml.LoadXml('<toast duration="short"><visual><binding template="ToastGeneric"><text>$safeTitle</text><text>$safeMessage</text></binding></visual><audio silent="true"/></toast>')
`$appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier(`$appId).Show([Windows.UI.Notifications.ToastNotification]::new(`$xml))
"@
        powershell.exe -NoProfile -ExecutionPolicy Bypass -Command $script
    } catch {
        # Toast failures are non-fatal
    }
}

# Console writer that prefixes every line with a wall-clock timestamp and (if set) the
# current iteration counter. Used by Parse-JsonLine so the parsed view of stream-json
# mirrors Log() formatting. Honours the LastWasUnstamped state so banner→stream
# transitions get a single blank-line separator.
#
# Console-only by design — the log file already captures raw stream-json upstream in
# Invoke-SandboxRun, so duplicating the parsed view there would just bloat the file.
function Write-StampedLine($Text, [System.ConsoleColor]$ForegroundColor) {
    if ($script:LastWasUnstamped -and -not $script:LastUnstampedBlank) {
        Write-Host ''
    }
    $script:LastWasUnstamped = $false
    $script:LastUnstampedBlank = $false

    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $iter = if ($script:IterationLabel) { " $script:IterationLabel" } else { '' }
    $line = "[$ts]$iter │ $Text"
    if ($ForegroundColor) {
        Write-Host $line -ForegroundColor $ForegroundColor
    } else {
        Write-Host $line
    }
    # Match Log()'s behaviour: emit a blank separator after wrapped lines.
    if ($script:TerminalWidth -and $line.Length -gt $script:TerminalWidth) {
        Write-Host ''
    }
}

# Parse a single line of stream-json into human-readable output.
# Uses ConvertFrom-Json instead of the bash grep/sed approach.
function Parse-JsonLine($Line) {
    # Non-JSON lines pass through (iteration banners, status messages)
    if (-not $Line.StartsWith('{')) {
        Write-StampedLine $Line
        return
    }

    try {
        $json = $Line | ConvertFrom-Json
    } catch {
        return
    }

    switch ($json.type) {
        'system' {
            if ($json.model) {
                Write-StampedLine "  [session] model=$($json.model) session=$($json.session_id)"
            }
        }
        'assistant' {
            # Extract text content from content blocks
            if ($json.message -and $json.message.content) {
                foreach ($block in $json.message.content) {
                    if ($block.type -eq 'text' -and $block.text -and $block.text.Trim()) {
                        $text = $block.text -replace '\\n', ' ' -replace '\\t', ' '
                        Write-StampedLine "  $text"
                    }
                    if ($block.type -eq 'tool_use' -and $block.name) {
                        $toolName = $block.name
                        $input = $block.input

                        $padded = $toolName.PadRight(6)
                        switch ($toolName) {
                            { $_ -in 'Read', 'Glob', 'Grep' } {
                                $fpath = if ($input.file_path) { $input.file_path } else { $input.pattern }
                                Write-StampedLine "  -> $padded  $fpath"
                            }
                            { $_ -in 'Write', 'Edit' } {
                                Write-StampedLine "  -> $padded  $($input.file_path)"
                            }
                            'Bash' {
                                Write-StampedLine "  -> $padded  $($input.command)"
                            }
                            default {
                                Write-StampedLine "  -> $padded"
                            }
                        }
                    }
                }
            }
        }
        'user' {
            # Only show errors
            if ($json.message -and $json.message.content) {
                foreach ($block in $json.message.content) {
                    if ($block.is_error) {
                        $err = $block.content
                        if (-not $err -and $block.content -match '<tool_use_error>([^<]*)</tool_use_error>') {
                            $err = $Matches[1]
                        }
                        if ($err) { Write-StampedLine "  ✗ ERROR: $err" -ForegroundColor Red }
                    }
                }
            }
        }
        'result' {
            if ($json.result) {
                # Raw Write-Host blanks (rather than going through Write-StampedLine "" -NoTimestamp)
                # are intentional here — they bracket the result block visually without
                # mutating LastWasUnstamped/LastUnstampedBlank, since the surrounding stream
                # already managed the state correctly.
                Write-Host ""
                Write-StampedLine "  --- Result ---"
                Write-StampedLine "  $($json.result)"
                Write-Host ""
            }
            $cost = $json.cost_usd
            $duration = $json.duration_ms
            $turns = $json.num_turns
            if ($cost -or $duration) {
                $secs = if ($duration) { [math]::Round($duration / 1000, 1) } else { '?' }
                $costStr = if ($null -ne $cost) { $cost } else { '?' }
                $turnsStr = if ($null -ne $turns) { $turns } else { '?' }
                Write-StampedLine "  └ cost: `$$costStr   duration: ${secs}s   turns: $turnsStr"
            }
        }
    }
}

# Run a prompt through the sandbox, stream-json output, tee to log file and
# (optionally) an iteration-output file for completion checks. Uses sonnet.
#
# Uses `docker sandbox exec` (not `run`) so the sandbox can be reused across
# iterations without the second-invocation hang/137 that `run` historically
# triggered. -w is required so cwd matches the host-style mount path the
# loop computes for $claudeMdPath etc — without it cwd defaults to
# /home/agent/workspace and prompt-supplied paths fall outside cwd, which
# triggers a permission prompt that the autonomous loop can't answer.
# No -i: claude with -p reads the prompt from argv, not stdin; -i would
# leave stdin open and trigger a 3s "no stdin data" warning.
function Invoke-SandboxRun {
    param(
        [Parameter(Mandatory)][string]$SandboxName,
        [Parameter(Mandatory)][string]$Prompt,
        [Parameter(Mandatory)][string]$LogFile,
        [Parameter(Mandatory)][string]$WorkDir,
        [string]$IterationOutput,
        [string]$Model = 'sonnet',
        [int]$WatchdogSeconds = 60,
        [int]$StagnationSeconds = 900,
        [string]$FreshHomeDir = '',
        [switch]$DebugMode
    )

    # Fresh-HOME mode (A2 hypothesis test): if FreshHomeDir is set, prep a
    # per-call $HOME inside the sandbox by copying /home/agent/.claude minus
    # transient state subdirs, then run claude with --env HOME=$FreshHomeDir.
    # Goal: starve the iter-2+ deadlock of any cross-iteration state under ~/.claude.
    if ($FreshHomeDir) {
        $prepSw = [System.Diagnostics.Stopwatch]::StartNew()
        # rsync (not cp+rm) so transient state never gets copied in the first place.
        # Excludes mirror the state subdirs Reset-SandboxState wipes, plus *.lock.
        # Mirror the entire /home/agent into $FreshHomeDir, excluding only the
        # transient state under .claude. Earlier we copied just .claude — that
        # broke git (no .gitconfig → safe.directory missing → "dubious ownership"
        # exit 128) and would break anything else relying on $HOME dotfiles.
        $prepScript = "set -e; mkdir -p '$FreshHomeDir'; rsync -a --exclude='.claude/projects' --exclude='.claude/sessions' --exclude='.claude/session-env' --exclude='.claude/shell-snapshots' --exclude='.claude/backups' --exclude='.claude/downloads' --exclude='.claude/statsig' --exclude='.claude/*.lock' /home/agent/ '$FreshHomeDir/'"
        try {
            docker sandbox exec $SandboxName bash -c $prepScript 2>&1 | ForEach-Object {
                if ($_) { Add-Content -Path $LogFile -Value "[fresh-home] $_" }
            }
            $prepSw.Stop()
            Add-Content -Path $LogFile -Value ("[fresh-home] prepared {0} in {1:N1}s" -f $FreshHomeDir, $prepSw.Elapsed.TotalSeconds)
        } catch {
            Add-Content -Path $LogFile -Value "[fresh-home] WARNING: prep failed: $_"
        }
    }

    # Sentinel file: touched on first claude output. Watchdog uses it to
    # distinguish "claude is just slow" from "claude is hung from the start."
    $sentinel = Join-Path $env:TEMP "ralph-claude-output-$(Get-Random).flag"

    # Watchdog: heavy /proc + network forensic dump triggered when claude is
    # silent for $WatchdogSeconds. Only attached in -DebugMode because the
    # in-place-reset path is now reliable (fresh-HOME); a 60s silence in normal
    # operation is just claude warming up, not a hang we need to dump.
    # When debugging a regression, -DebugMode reattaches the dump so a true hang
    # leaves forensics in the log even when the parent is killed mid-poll.
    $watchdogJob = $null
    if ($DebugMode) {
    # Watchdog writes its diagnostic capture *directly to the log file* rather
    # than buffering in Job output. Previous design buffered output and only
    # surfaced it in the parent's `finally` block — but on a true hang the
    # parent never reaches `finally`, so the diagnostic never landed. Direct
    # log writes ensure forensics are visible the moment the watchdog fires.
    # Fresh-HOME mode points $HOME at a per-call /tmp dir (see prep block above),
    # so claude's writable state is there, NOT at /home/agent/.claude (which is the
    # readonly host mount). Watchdog forensics must drill into the actual HOME or
    # the .claude probes look at the wrong tree. Pass via --env CLAUDE_HOME so the
    # bash heredoc stays single-quoted (no PS var-expansion gymnastics).
    $effectiveHome = if ($FreshHomeDir) { "$FreshHomeDir/.claude" } else { '/home/agent/.claude' }

    $watchdogJob = Start-Job -ScriptBlock {
        param($sentinel, $sandbox, $delay, $logFile, $claudeHome)
        Start-Sleep -Seconds $delay
        if (-not (Test-Path $sentinel)) {
            Add-Content -Path $logFile -Value ""
            Add-Content -Path $logFile -Value "[watchdog] === BEGIN (no claude output after ${delay}s, CLAUDE_HOME=$claudeHome) ==="
            # Captures process state, memory, AND network state. The 2026-04-29
            # iter-1-retry hang showed claude alive with zero open sockets — so
            # the hang is network-related, not process-state. ss -tnpa surfaces
            # all sockets (incl. listening + non-established); resolv/proxy/curl
            # probes pin down whether DNS, proxy, or upstream is the gate.
            $diag = docker sandbox exec --env "CLAUDE_HOME=$claudeHome" $sandbox bash -c @'
echo "---ps auxf---"
ps auxf | head -60
echo "---pgrep claude/node/dotnet---"
pgrep -af "claude|node|dotnet"
echo "---ls $CLAUDE_HOME---"
ls "$CLAUDE_HOME/" 2>&1
echo "---memory.current---"
cat /sys/fs/cgroup/memory.current 2>/dev/null
echo "---ss -anpe (ALL sockets incl UNIX/netlink)---"
ss -anpe 2>/dev/null | head -60
echo "---/proc/net/unix (top of table)---"
cat /proc/net/unix 2>/dev/null | head -30
echo "---/etc/resolv.conf---"
cat /etc/resolv.conf 2>/dev/null
echo "---proxy env vars---"
env | grep -iE "proxy|http_|https_|no_proxy" | head -20
echo "---curl probe to api.anthropic.com---"
timeout 5 curl -sSv --max-time 4 -o /dev/null https://api.anthropic.com/ 2>&1 | head -30
echo "---$CLAUDE_HOME/projects/* sessions---"
ls -la "$CLAUDE_HOME"/projects/*/ 2>&1 | head -30
# Drill into claude PID to find what kernel-level state is blocking it.
# wchan = kernel function it is sleeping in (futex_wait, pipe_read, etc).
# syscall = current syscall args. fd/ lists open files (look for *.lock).
CPID=$(pgrep -x claude | head -1)
if [ -n "$CPID" ]; then
  echo "---/proc/$CPID/wchan---"
  cat /proc/$CPID/wchan 2>&1; echo
  echo "---/proc/$CPID/syscall---"
  cat /proc/$CPID/syscall 2>&1
  echo "---/proc/$CPID/status (key fields)---"
  grep -E "^(State|Threads|VmRSS|voluntary|nonvoluntary)" /proc/$CPID/status 2>&1
  echo "---/proc/$CPID/fd (open files)---"
  ls -la /proc/$CPID/fd/ 2>&1 | head -40
  echo "---claude socket peers (per fd) ---"
  for fd in $(ls /proc/$CPID/fd/ 2>/dev/null); do
    tgt=$(readlink /proc/$CPID/fd/$fd 2>/dev/null)
    if [[ "$tgt" == socket:* ]]; then
      inode=$(echo "$tgt" | sed -E "s/socket:\[(.*)\]/\1/")
      echo "fd=$fd $tgt"
      # Peer lookup in /proc/net/{unix,tcp,udp,netlink}
      grep -wE "[ ]${inode}[ ]" /proc/net/unix 2>/dev/null | head -2
      awk -v i=$inode "\$10 == i" /proc/net/tcp 2>/dev/null | head -2
      awk -v i=$inode "\$10 == i" /proc/net/udp 2>/dev/null | head -2
    fi
  done
  echo "---/proc/$CPID/stack (kernel stack)---"
  cat /proc/$CPID/stack 2>&1 | head -20
  echo "---/proc/$CPID/task threads---"
  ls /proc/$CPID/task/ 2>&1 | head -20
  echo "---per-thread wchan---"
  for tid in $(ls /proc/$CPID/task/ 2>/dev/null | head -10); do
    echo "tid=$tid wchan=$(cat /proc/$CPID/task/$tid/wchan 2>/dev/null) state=$(awk "/^State:/ {print \$2}" /proc/$CPID/task/$tid/status 2>/dev/null)"
  done
  echo "---/proc/$CPID/io (snapshot 1)---"
  cat /proc/$CPID/io 2>&1
  echo "---/proc/$CPID/fdinfo/4 (eventpoll watchset)---"
  cat /proc/$CPID/fdinfo/4 2>&1 | head -30
  echo "---fdinfo for socket fd 13 (idle proxy connection?)---"
  cat /proc/$CPID/fdinfo/13 2>&1 | head -10
  echo "---fdinfo for timerfds (when do they fire?)---"
  for fd in 5 7 8 15; do
    echo "fd=$fd:"; cat /proc/$CPID/fdinfo/$fd 2>&1 | head -10
  done
  echo "---sleeping 30s, then snapshot 2 of /proc/$CPID/io to detect activity---"
  sleep 30
  echo "---/proc/$CPID/io (snapshot 2 after 30s)---"
  cat /proc/$CPID/io 2>&1
  echo "---/proc/$CPID/status (snapshot 2 ctxt switches)---"
  grep -E "^(voluntary|nonvoluntary)" /proc/$CPID/status 2>&1
  echo "---/proc/$CPID/wchan (snapshot 2)---"
  cat /proc/$CPID/wchan 2>&1; echo
else
  echo "---no claude PID found---"
fi
'@ 2>&1
            $diag | ForEach-Object { Add-Content -Path $logFile -Value "[watchdog] $_" }
            Add-Content -Path $logFile -Value "[watchdog] === END ==="
        }
    } -ArgumentList $sentinel, $SandboxName, $WatchdogSeconds, $LogFile, $effectiveHome
    }

    # Run docker exec in a job so we can kill it on stagnation without relying
    # on the pipeline producing output. Polling loop drains output every 200ms
    # AND checks stagnation regardless of whether output is flowing — so a
    # zero-output hang gets killed at $StagnationSeconds, not "forever."
    $execJob = Start-Job -ScriptBlock {
        param($sandbox, $workDir, $model, $prompt, $freshHome)
        if ($freshHome) {
            docker sandbox exec --workdir $workDir --env "HOME=$freshHome" $sandbox claude `
                --model $model --permission-mode acceptEdits --verbose --output-format stream-json -p $prompt 2>&1
        } else {
            docker sandbox exec --workdir $workDir $sandbox claude `
                --model $model --permission-mode acceptEdits --verbose --output-format stream-json -p $prompt 2>&1
        }
    } -ArgumentList $SandboxName, $WorkDir, $Model, $Prompt, $FreshHomeDir

    $lastOutputAt = Get-Date
    $stagnated = $false
    try {
        while ($execJob.State -eq 'Running') {
            $newLines = Receive-Job $execJob -ErrorAction SilentlyContinue
            if ($newLines) {
                $lastOutputAt = Get-Date
                if (-not (Test-Path $sentinel)) { Set-Content -Path $sentinel -Value '' -ErrorAction SilentlyContinue }
                foreach ($line in $newLines) {
                    $lineStr = $line.ToString()
                    $lineStr | Add-Content $LogFile
                    if ($IterationOutput) { $lineStr | Add-Content $IterationOutput }
                    Parse-JsonLine $lineStr
                }
            }
            if (((Get-Date) - $lastOutputAt).TotalSeconds -gt $StagnationSeconds) {
                $stagnated = $true
                break
            }
            Start-Sleep -Milliseconds 200
        }

        # Drain any final output after job state transitions out of Running.
        $finalLines = Receive-Job $execJob -ErrorAction SilentlyContinue
        if ($finalLines) {
            foreach ($line in $finalLines) {
                $lineStr = $line.ToString()
                $lineStr | Add-Content $LogFile
                if ($IterationOutput) { $lineStr | Add-Content $IterationOutput }
                Parse-JsonLine $lineStr
            }
        }

        if ($stagnated) {
            $silentFor = ((Get-Date) - $lastOutputAt).TotalSeconds
            Log ("Invoke-SandboxRun: no output for {0:N0}s — assumed hung, killing exec" -f $silentFor)
            # Stop-Job kills the host pwsh worker + its docker CLI child.
            # The in-sandbox claude is orphaned by that — kill it explicitly so
            # the next iteration doesn't race with a corpse.
            Stop-Job $execJob -ErrorAction SilentlyContinue
            try { docker sandbox exec $SandboxName pkill -9 -x claude 2>$null } catch { }
        }
    } catch {
        Log "Invoke-SandboxRun error: $_"
    } finally {
        Remove-Item $sentinel -ErrorAction SilentlyContinue
        Stop-Job $execJob -ErrorAction SilentlyContinue
        Remove-Job $execJob -Force -ErrorAction SilentlyContinue
        if ($watchdogJob) {
            Stop-Job $watchdogJob -ErrorAction SilentlyContinue
            Remove-Job $watchdogJob -Force -ErrorAction SilentlyContinue
        }
    }
}

# Lightweight in-place state reset between iterations. Replaces the full
# rm + create cycle (~5min) when -LegacyRecreate is not set. Kills any
# orphan claude/node/dotnet processes from the previous iteration and
# clears claude session lockfiles so the next exec starts on a clean slate.
# Total cost: ~1-3s vs 297s for full recreate.
# Wrapper used between iterations and before each post-completion review run.
# Picks Recreate-Sandbox (full rm+create, slow but bulletproof) when -Legacy is
# set, otherwise Reset-SandboxState (in-place cleanup, fast). Centralised here so
# the iteration loop and completion path branch in one place, not seven.
function Cycle-Sandbox {
    param(
        [Parameter(Mandatory)][string]$SandboxName,
        [Parameter(Mandatory)][string]$TemplateName,
        [Parameter(Mandatory)][array]$MountArgs,
        [switch]$Legacy
    )
    if ($Legacy) {
        Recreate-Sandbox -SandboxName $SandboxName -TemplateName $TemplateName -MountArgs $MountArgs
    } else {
        Reset-SandboxState -SandboxName $SandboxName
    }
}

# Snapshot sandbox state for hang diagnosis. Fires synchronously and writes
# everything to the main log so failure forensics live alongside the timing data.
# Cheap (~1-2s) so we can call before every iteration without slowing the loop.
function Capture-SandboxDiagnostics {
    param(
        [Parameter(Mandatory)][string]$SandboxName,
        [Parameter(Mandatory)][string]$Label
    )
    Log "=== diag[$Label] BEGIN ==="
    try {
        docker sandbox exec $SandboxName bash -c @'
echo "--- ps auxf ---"
ps auxf 2>&1 | head -60
echo "--- free -m ---"
free -m 2>&1
echo "--- cgroup memory ---"
echo "memory.max=$(cat /sys/fs/cgroup/memory.max 2>/dev/null)"
echo "memory.current=$(cat /sys/fs/cgroup/memory.current 2>/dev/null)"
echo "memory.peak=$(cat /sys/fs/cgroup/memory.peak 2>/dev/null)"
echo "memory.events=$(cat /sys/fs/cgroup/memory.events 2>/dev/null | tr "\n" " ")"
echo "--- claude state files ---"
ls -la /home/agent/.claude/ 2>&1 | head -20
find /home/agent/.claude -maxdepth 4 \( -name "*.lock" -o -name "*.pid" -o -name "*.sock" \) 2>/dev/null | head -20
echo "--- running claude/node/dotnet pids ---"
pgrep -af "claude|node|dotnet" 2>&1
echo "--- open sockets (claude relevance) ---"
ss -tnp 2>/dev/null | head -20
echo "--- recent dmesg (oom?) ---"
dmesg 2>/dev/null | tail -20
echo "--- /tmp/build presence ---"
ls -la /tmp/build 2>/dev/null | head -5 || echo "no /tmp/build"
'@ 2>&1 | ForEach-Object { if ($_) { Log "  $_" } }
    } catch {
        Log "  diag capture failed: $_"
    }
    Log "=== diag[$Label] END ==="
}

function Reset-SandboxState {
    param(
        [Parameter(Mandatory)][string]$SandboxName
    )
    Log "Resetting sandbox state in-place (skipping full recreate)..."
    $totalSw = [System.Diagnostics.Stopwatch]::StartNew()

    # Use `pkill -x <name>` (exact process-name match) rather than `pkill -f <pattern>`
    # because -f matches against the full /proc/PID/cmdline. Our previous bash wrapper
    # had "claude" inside its own cmdline, so `pkill -f claude` killed the bash parent
    # before subsequent commands ran and let the actual claude orphan survive. -x
    # matches argv[0] basename only, so pkill/bash/this script are all immune.
    #
    # Graceful kill first (SIGTERM, 3s grace) so claude can finalise its session
    # jsonl and release locks. SIGKILL after, in case claude hangs during cleanup.
    # Without this, the session jsonl is left in an inconsistent state and the
    # next iteration's claude hangs at startup trying to index it (diagnosed via
    # /proc introspection: missed wakeup between main thread and worker thread
    # holding the half-written session file).
    try {
        # One exec per signal so a failure on one kill doesn't abort the rest.
        docker sandbox exec $SandboxName pkill -TERM -x claude 2>$null
        docker sandbox exec $SandboxName pkill -TERM -x node 2>$null
        docker sandbox exec $SandboxName pkill -TERM -x dotnet 2>$null
        Start-Sleep -Seconds 3
        docker sandbox exec $SandboxName pkill -9 -x claude 2>$null
        docker sandbox exec $SandboxName pkill -9 -x node 2>$null
        docker sandbox exec $SandboxName pkill -9 -x dotnet 2>$null
        # Wipe transient session state so iter 2's claude doesn't get confused
        # by iter 1's session jsonl (whose write may have been incomplete even
        # with SIGTERM). Preserves projects/*/memory/ which is the auto-memory
        # store and IS supposed to persist across iterations.
        docker sandbox exec $SandboxName bash -lc 'rm -f /home/agent/.claude/*.lock /home/agent/.claude/projects/*/locks/* /home/agent/.claude/projects/*/*.jsonl /home/agent/.claude/sessions/* 2>/dev/null; true' 2>$null
    } catch {
        Log "WARNING: Reset-SandboxState failed: $_"
    }
    $totalSw.Stop()
    Log ("Sandbox state reset in {0:N1}s." -f $totalSw.Elapsed.TotalSeconds)
}

function Assert-PowerShellCore {
    if ($PSVersionTable.PSEdition -ne 'Core') {
        Log "This script must be run in PowerShell Core (pwsh). You are using Windows PowerShell $($PSVersionTable.PSVersion)."
        exit 1
    }
}

function Assert-AzureLogin {
    param(
        [Parameter(Mandatory)][string]$TenantId,
        [Parameter(Mandatory)][string]$RegistryName
    )

    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        Write-Host "ERROR: Azure CLI (az) not found in PATH. Install from https://aka.ms/installazurecli"
        exit 1
    }

    # Check if already logged into the correct tenant
    $currentTenant = $null
    try {
        $currentTenant = (az account show --query tenantId -o tsv 2>$null)
    } catch { }

    if ($currentTenant -ne $TenantId) {
        Write-Host "Azure CLI is not logged into tenant $TenantId."
        $response = Read-Host "Run 'az login --tenant $TenantId'? (Y/n)"
        if ($response -and $response -notmatch '^[Yy]') {
            Write-Host "ERROR: Azure login is required to pull the sandbox image from ACR."
            exit 1
        }
        az login --tenant $TenantId --output none
        if ($LASTEXITCODE -ne 0) {
            Write-Host "ERROR: Azure login failed"
            exit 1
        }
    }

    # Ensure correct subscription
    $RequiredSubscriptionId = '1864af5b-2331-4441-8e45-4817201344ae'
    $currentSub = $null
    try { $currentSub = (az account show --query id -o tsv 2>$null) } catch { }
    if ($currentSub -ne $RequiredSubscriptionId) {
        Write-Host "Switching Azure subscription to $RequiredSubscriptionId..."
        az account set --subscription $RequiredSubscriptionId
        if ($LASTEXITCODE -ne 0) {
            Write-Host "ERROR: Failed to set Azure subscription"
            exit 1
        }
    }

    # Authenticate to ACR
    Write-Host "Authenticating to ACR '$RegistryName'..."
    az acr login --name $RegistryName
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: ACR login failed for '$RegistryName'"
        exit 1
    }
}

function Ensure-LatestSandboxImage {
    param(
        [Parameter(Mandatory)][string]$ImageRef,
        [Parameter(Mandatory)][string]$LocalTag
    )

    # Snapshot image ID before pull to detect changes afterwards
    $idBefore = docker inspect --format '{{.Id}}' $ImageRef 2>$null

    # Pull from ACR — let docker write directly to terminal for progress bars
    Write-Host "Pulling sandbox image from ACR..."
    docker pull $ImageRef
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Failed to pull sandbox image '$ImageRef'"
        exit 1
    }

    $idAfter = docker inspect --format '{{.Id}}' $ImageRef 2>$null
    $imageUpdated = ($idBefore -ne $idAfter)
    if ($imageUpdated) {
        Write-Host "Sandbox image updated."
        # Remove the old image that lost its tag after the pull
        docker image prune -f | Out-Null
    } else {
        Write-Host "Sandbox image is up to date."
    }

    # Rebuild as a local-only image to strip ACR RepoDigests metadata.
    # Without this, docker sandbox create tries to resolve the image against
    # the registry even when it's cached locally, causing 403 errors.
    # Only rebuild if we pulled a new image or the local tag doesn't exist yet.
    $localTagExists = docker image inspect $LocalTag >$null 2>&1; $localTagExists = ($LASTEXITCODE -eq 0)
    if ($imageUpdated -or -not $localTagExists) {
        Write-Host "Rebuilding as local image '$LocalTag'..."
        "FROM $ImageRef" | docker build --provenance=false -t $LocalTag -
        if ($LASTEXITCODE -ne 0) {
            Write-Host "ERROR: Failed to rebuild sandbox image as '$LocalTag'"
            exit 1
        }
    } else {
        Write-Host "Local image '$LocalTag' is up to date."
    }

    $script:SandboxImageUpdated = $imageUpdated
}

function Sync-ProxyConfig {
    param(
        [Parameter(Mandatory)][string]$ScriptDir
    )

    $proxySource = Join-Path $ScriptDir "config/proxy-config.yml"
    $sandboxdDir = Join-Path $env:USERPROFILE ".sandboxd"
    $proxyTarget = Join-Path $sandboxdDir "proxy-config.json"

    if (-not (Test-Path $proxySource)) {
        Write-Host "ERROR: $proxySource not found"
        exit 1
    }

    if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
        Write-Host "Installing powershell-yaml module..."
        Install-Module -Name powershell-yaml -Force -Scope CurrentUser
    }
    Import-Module powershell-yaml

    $yamlContent = ConvertFrom-Yaml (Get-Content $proxySource -Raw) -Ordered

    # Guard against powershell-yaml converting empty YAML arrays [] to $null
    foreach ($key in @('allowedDomains', 'blockedDomains', 'blockedCIDRs', 'bypassDomains', 'bypassCIDRs')) {
        if ($null -eq $yamlContent.network[$key]) {
            $yamlContent.network[$key] = @()
        }
    }

    # Merge per-MCP-server allowedDomains into network.allowedDomains
    # MCP sections are any top-level key that isn't 'policy' or 'network'
    $mcpSections = $yamlContent.Keys | Where-Object { $_ -notin @('policy', 'network') }
    foreach ($section in $mcpSections) {
        $mcpDomains = $yamlContent[$section].allowedDomains
        if ($mcpDomains) {
            $yamlContent.network.allowedDomains += $mcpDomains
        }
        $yamlContent.Remove($section)
    }

    $generatedJson = $yamlContent | ConvertTo-Json -Depth 5

    if (-not (Test-Path $sandboxdDir)) {
        New-Item -ItemType Directory -Path $sandboxdDir -Force | Out-Null
    }

    # Write to temp file for hash comparison
    $tempFile = Join-Path $sandboxdDir "proxy-config.json.tmp"
    Set-Content -Path $tempFile -Value $generatedJson -Encoding UTF8 -Force

    if (Test-Path $proxyTarget) {
        $sourceHash = (Get-FileHash $tempFile -Algorithm SHA256).Hash
        $targetHash = (Get-FileHash $proxyTarget -Algorithm SHA256).Hash
        if ($sourceHash -eq $targetHash) {
            Write-Host "proxy-config.json is up to date, no copy needed."
            Remove-Item $tempFile -Force
            return $false
        } else {
            $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
            $backupPath = "$proxyTarget.backup-$timestamp"
            Rename-Item $proxyTarget $backupPath
            Write-Host "Backup created: $(Split-Path $backupPath -Leaf)"
            Move-Item $tempFile $proxyTarget -Force
            Write-Host "proxy-config.json updated."
            return $true
        }
    } else {
        Move-Item $tempFile $proxyTarget -Force
        Write-Host "proxy-config.json written to ~/.sandboxd/"
        return $true
    }
}

function ConvertTo-SafeImageFilename($ImageName) {
    return ($ImageName -replace '[/:]', '--') + ".tar"
}

# Get the main repo root, resolving through worktree .git files if needed.
# In a normal repo, returns the repo root. In a worktree, traces the .git file
# back to the main repo's root (e.g., .claude/worktrees/xyz → C:\dev\freemarket\Repo).
function Get-MainRepoRoot {
    param([Parameter(Mandatory)][string]$RepoRoot)

    $gitPath = Join-Path $RepoRoot ".git"
    if ((Test-Path $gitPath) -and -not (Test-Path $gitPath -PathType Container)) {
        $gitContent = (Get-Content $gitPath -Raw).Trim()
        if ($gitContent -match '^gitdir:\s*(.+)$') {
            $gitDir = $Matches[1].Trim()
            # Git for Windows writes Unix-style paths (e.g. /c/dev/...) — convert to Windows
            if ($gitDir -match '^/([a-zA-Z])/(.+)$') {
                $gitDir = "$($Matches[1].ToUpper()):\$($Matches[2] -replace '/', '\')"
            }
            if (-not [System.IO.Path]::IsPathRooted($gitDir)) {
                $gitDir = [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $gitDir))
            }
            # gitDir = <main-repo>/.git/worktrees/<name> — 3 levels up to main repo root
            return Split-Path (Split-Path (Split-Path $gitDir -Parent) -Parent) -Parent
        }
    }
    return (Resolve-Path $RepoRoot).Path
}

# Resolve a sibling repo by name, handling both normal layout and worktrees.
# Normal: C:\dev\freemarket\Repo\..\PlatformCode
# Worktree: traces .git file to find main repo, then looks for sibling there.
# Returns $null if the sibling repo is not found.
function Resolve-SiblingRepo {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$Name
    )

    # Direct sibling (normal layout)
    $direct = Join-Path (Split-Path $RepoRoot -Parent) $Name
    if (Test-Path $direct) {
        return (Resolve-Path $direct).Path
    }

    # Worktree: resolve from the main repo's parent
    $mainRoot = Get-MainRepoRoot -RepoRoot $RepoRoot
    if ($mainRoot -ne (Resolve-Path $RepoRoot).Path) {
        $sibling = Join-Path (Split-Path $mainRoot -Parent) $Name
        if (Test-Path $sibling) {
            return (Resolve-Path $sibling).Path
        }
    }

    return $null
}
