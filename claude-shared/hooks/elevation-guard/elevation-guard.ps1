<#
.SYNOPSIS
    PreToolUse elevation guard (Windows).

.DESCRIPTION
    Blocks any tool call when Claude Code is running with Administrator privileges.
    On block: emits two stderr lines and exits 2 (Claude Code contract:
    PreToolUse exit 2 = deny + feed stderr to Claude / OTEL log).

      1. Human-readable block reason (relayed by Claude to the user).
      2. Stable, greppable OTEL sentinel:
         CLAUDE_ELEVATION_BLOCK tool=<TOOL> user=<USER> os=Windows pid=<PID>

    Fails open (exit 0) on any unexpected error so a broken hook can never
    wedge Claude Code.

    Compatible with Windows PowerShell 5.1 (built into Windows) — does NOT
    require pwsh / PowerShell Core.
#>

trap { exit 0 }

# Read PreToolUse JSON payload from stdin (best-effort; used to enrich the
# sentinel and the Datadog log). Skip when stdin is a console — ReadToEnd would
# block forever waiting for an EOF that an interactive terminal never sends.
$toolName = 'unknown'
$rawStdin = $null
if ([Console]::IsInputRedirected) {
    try {
        $rawStdin = [Console]::In.ReadToEnd()
        if ($rawStdin) {
            $payload = $rawStdin | ConvertFrom-Json -ErrorAction Stop
            if ($payload.tool_name) { $toolName = [string]$payload.tool_name }
        }
    } catch {
        # Ignore — sentinel just reports tool=unknown.
    }
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if ($isAdmin) {
    # Prefer UPN (user@domain) over the down-level DOMAIN\user form. Use an
    # absolute path to System32\whoami.exe so a shadowing whoami on PATH (e.g.
    # GNU coreutils via Git Bash) cannot poison the lookup. /upn errors for
    # local-only accounts, in which case we fall back to $identity.Name.
    $user = $identity.Name
    try {
        $whoami = Join-Path ([Environment]::SystemDirectory) 'whoami.exe'
        $upn = (& $whoami /upn 2>$null)
        if ($LASTEXITCODE -eq 0 -and $upn) { $user = ($upn | Select-Object -First 1).Trim() }
    } catch { }
    $human = "Blocked: Claude Code is running in an elevated/Administrator shell ($user). Restart Claude Code from a non-elevated shell to proceed."
    $sentinel = "CLAUDE_ELEVATION_BLOCK tool=$toolName user=$user os=Windows pid=$PID"
    [Console]::Error.WriteLine($human)
    [Console]::Error.WriteLine($sentinel)

    try {
        . (Join-Path $PSScriptRoot '..\lib\datadog-log\post.ps1')
        Send-DatadogHookLog `
            -Hook 'elevation-guard' `
            -HookEvent 'PreToolUse' `
            -ToolName $toolName `
            -Outcome 'block' `
            -Reason 'elevated_shell' `
            -Message $human `
            -StdinJson $rawStdin
    } catch { }

    exit 2
}

exit 0
