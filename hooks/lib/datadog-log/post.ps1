<#
.SYNOPSIS
    Datadog log helper for Claude Code hooks.

.DESCRIPTION
    Exposes Send-DatadogHookLog. Hook scripts dot-source this file and call
    the function with hook-specific values; the helper auto-fills the
    environment envelope (host, os, user, pid, session, claude_code.version,
    terminal, ddsource, ddtags base, event.timestamp) and POSTs the merged
    payload to the Datadog browser-intake endpoint.

    The Client Token is read from the sibling 'client-token' file. If the
    file is missing or empty the function returns silently — telemetry must
    never wedge a hook.

    The whole body is wrapped in try/catch so any HTTP/DNS/parse failure is
    swallowed.

    Required for the caller: -Hook, -HookEvent, -ToolName, -Outcome, -Reason.
#>

function Send-DatadogHookLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Hook,
        [Parameter(Mandatory)] [string]$HookEvent,
        [string]$ToolName = '',
        [Parameter(Mandatory)] [string]$Outcome,
        [Parameter(Mandatory)] [string]$Reason,
        [string]$EventName = 'hook_block',
        [string]$Status = 'warning',
        [string]$Message,
        [string]$StdinJson,
        [hashtable]$Extra
    )

    try {
        $tokenPath = Join-Path $PSScriptRoot 'client-token'
        if (-not (Test-Path -LiteralPath $tokenPath)) { return }
        $token = (Get-Content -LiteralPath $tokenPath -Raw -ErrorAction Stop).Trim()
        if (-not $token) { return }

        # SessionStart / Stop / Notification hooks have no associated tool —
        # callers pass '' or 'none' to indicate that. Don't append a colon
        # suffix in that case; hook_name = HookEvent is more accurate.
        $hasTool = $ToolName -and $ToolName -ne 'none'
        $hookName = if ($hasTool) { "$HookEvent`:$ToolName" } else { $HookEvent }

        # Resolve email Claude Code is authenticated as. Prefer the
        # oauthAccount.emailAddress field in ~/.claude.json (the real
        # Claude identity), fall back to the Windows UPN if the file
        # is missing or unparseable.
        $userEmail = $null
        try {
            $claudeJsonPath = Join-Path $env:USERPROFILE '.claude.json'
            if (Test-Path -LiteralPath $claudeJsonPath) {
                $cc = Get-Content -LiteralPath $claudeJsonPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                if ($cc.oauthAccount.emailAddress -and $cc.oauthAccount.emailAddress -match '@') {
                    $userEmail = [string]$cc.oauthAccount.emailAddress
                }
            }
        } catch { }
        if (-not $userEmail) {
            try {
                $whoami = Join-Path ([Environment]::SystemDirectory) 'whoami.exe'
                $upn = (& $whoami /upn 2>$null)
                if ($LASTEXITCODE -eq 0 -and $upn) {
                    $candidate = ($upn | Select-Object -First 1).Trim()
                    if ($candidate -match '@') { $userEmail = $candidate }
                }
            } catch { }
        }

        # Best-effort terminal detection.
        $terminalType = if ($env:WT_SESSION) { 'windows-terminal' }
                        elseif ($env:TERM_PROGRAM) { $env:TERM_PROGRAM }
                        elseif ($env:TERM) { $env:TERM }
                        else { 'unknown' }

        # Best-effort parent PID.
        $parentPid = $null
        try {
            $parentPid = (Get-CimInstance Win32_Process -Filter "ProcessId=$PID" -ErrorAction Stop).ParentProcessId
        } catch { }

        # Optional fields from PreToolUse stdin payload.
        $sessionId = $null; $transcriptPath = $null; $cwd = $null; $stdinSize = 0
        if ($StdinJson) {
            $stdinSize = [Text.Encoding]::UTF8.GetByteCount($StdinJson)
            try {
                $payload = $StdinJson | ConvertFrom-Json -ErrorAction Stop
                if ($payload.session_id)      { $sessionId      = [string]$payload.session_id }
                if ($payload.transcript_path) { $transcriptPath = [string]$payload.transcript_path }
                if ($payload.cwd)             { $cwd            = [string]$payload.cwd }
            } catch { }
        }

        if (-not $Message) {
            $who = if ($userEmail) { $userEmail } else { $env:USERNAME }
            $Message = "$Hook ${Outcome}ed $hookName for ${who} (${Reason})"
        }

        $tags = @(
            "hook:$Hook",
            "outcome:$Outcome",
            "reason:$Reason",
            "os.type:windows"
        ) -join ','

        $body = [ordered]@{
            service     = 'claude-code'
            ddsource    = 'claude-code-hook'
            ddtags      = $tags
            status      = $Status
            message     = $Message
            event       = [ordered]@{
                name      = $EventName
                timestamp = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
            }
            hook        = $Hook
            hook_event  = $HookEvent
            hook_name   = $hookName
            tool        = if ($hasTool) { $ToolName } else { $null }
            outcome     = $Outcome
            reason      = $Reason
            os          = [ordered]@{
                type    = 'windows'
                version = [string][Environment]::OSVersion.Version
            }
            host        = [ordered]@{
                name = $env:COMPUTERNAME
                arch = $env:PROCESSOR_ARCHITECTURE
            }
            user        = [ordered]@{ email = $userEmail; name = $env:USERNAME }
            pid         = $PID
            parent_pid  = $parentPid
            session     = [ordered]@{ id = $sessionId }
            transcript_path     = $transcriptPath
            cwd                 = $cwd
            tool_input_size_bytes = $stdinSize
            claude_code = [ordered]@{ version = $env:CLAUDE_CODE_VERSION }
            terminal    = [ordered]@{ type = $terminalType }
        }

        if ($Extra) {
            foreach ($k in $Extra.Keys) { $body[$k] = $Extra[$k] }
        }

        $json = $body | ConvertTo-Json -Depth 10 -Compress

        $url = 'https://browser-intake-datadoghq.eu/api/v2/logs' +
               "?dd-api-key=$token" +
               '&ddsource=claude-code-hook' +
               '&dd-evp-origin=claude-code-hook' +
               '&dd-evp-origin-version=0.1.0'

        $headers = @{
            'Content-Type' = 'text/plain;charset=UTF-8'
            'Origin'       = 'https://claude-code-hook.local'
        }

        Invoke-WebRequest -Uri $url -Method Post -Body $json -Headers $headers `
            -TimeoutSec 2 -UseBasicParsing -ErrorAction Stop | Out-Null
    } catch {
        # Fail open — telemetry must not wedge the hook.
    }
}
