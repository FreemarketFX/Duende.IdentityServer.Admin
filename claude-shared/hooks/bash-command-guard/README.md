# bash-command-guard

`PreToolUse` hook that inspects every `Bash` tool call against two regex lists:

- **`blocklist.txt`** — match → exit 2 (Claude sees a block message; user can override only by editing the list).
- **`warnlist.txt`** — match → exit 0 (allow), but a structured warn log is sent to Datadog. Use this to trial new restrictions without breaking workflows.

Both lists are case-insensitive regexes, one per line. `#` comments and blank lines are ignored.

## Why a hook and not just a permission deny

`.claude/settings.local.json` already has `Bash(az *)` in its deny list. That layer:

- Is per-machine (not shipped with the plugin).
- Only matches the literal `az` command, not chained-shell wrappers like `bash -c "az login"`.
- Cannot warn-without-blocking.

This hook is shipped with the plugin, inspects the *full* command string (so `bash -c`, `sh -c`, `cmd /c` chains all match), and supports the warn list. We keep the permission deny in place for defense-in-depth: the permission layer rejects the literal call before the hook even fires.

## What's blocked by default

The full block list lives in [`blocklist.txt`](./blocklist.txt). Categories:

- **Azure / cloud CLIs**: `az`, `Verb-Az*` PowerShell cmdlets, `azcopy`, `azureauth`, `swa`, `kubectl`, plus Azure REST/identity hostnames (`management.azure.com`, `login.microsoftonline.com`, `*.blob.core.windows.net`, etc.) and access-token verbs (`get-credentials`, `(get|print)-access-token`, which catches `gcloud auth print-access-token` too).
- **Secret managers**: `ksm` (Keeper).
- **Credential file reads**: `~/.ssh/id_*`, `~/.aws/credentials`, `~/.azure/(accessTokens|...)`, `~/.kube/config`, `~/.netrc`, `~/.docker/config.json`, `~/.git-credentials`, browser `Login Data`.
- **Credential-management CLIs**: `ssh-keyscan`, `cmdkey`, `vaultcmd`, `secret-tool`, macOS `security find-*-password`, `gh auth token`, `aws configure get`, `get-session-token`, `op (read|item|document)`, `pass show`, `keyring get`.
- **Project-scoped overrides**: `acli` invocations that reference an `AILV-<n>` ticket key block (regardless of subcommand). The bare `acli` (against any other project key) only warns — the AILV project carries content we treat as exfil-sensitive.

Short tokens (`ksm`, `swa`, `acli`) use a tighter left boundary than `\b` — `(^|[^[:alnum:]_-])token\b` — so neighbours like `linux-ksm-tools`, `static-swa-bin`, and `local-acli-tools` do not false-fire. See [`CLAUDE.md`](./CLAUDE.md) for the rationale.

## What's on the warn list

See [`warnlist.txt`](./warnlist.txt). Currently:

- SSH key tooling (`ssh-keygen`, `ssh-add`) — legitimate during setup, suspicious mid-session.
- Environment dumps (`printenv`, `env |`, `Get-ChildItem env:`) — common in debugging, but a known exfil pattern.
- Recon (`netstat`).
- AWS/GCP identity probes (`get-caller-identity`, `print-identity-token`).
- Atlassian CLI (`acli`) — agents reaching Jira/Confluence often = PII / ticket-content exfil risk.

Promote a warn pattern to the block list once Datadog shows the false-positive rate is acceptable.

## Adding or removing a pattern

1. Edit `blocklist.txt` or `warnlist.txt`. One regex per line. Escape literal `.` `(` `[` etc.
2. Add a test case to [`test-cases.json`](./test-cases.json) (positive **and** negative case if the pattern could false-fire).
3. Run the test harness:
   ```bash
   ./test-guard.sh         # bash
   ./test-guard.ps1        # PowerShell
   ```
4. Commit. The plugin version bump in `.claude-plugin/plugin.json` ensures consumers refresh their cache.

## Testing

`test-guard.sh` (bash) and `test-guard.ps1` (PowerShell) are dual-mode:

```bash
# Run the full matrix from test-cases.json (CI-friendly; non-zero exit on failure)
./test-guard.sh

# Single-shot — useful for exploring new patterns interactively
./test-guard.sh --command "az login"
./test-guard.sh --command "tar -azxvf foo.tgz"      # negative-test \baz\b
./test-guard.sh --command "Get-AzVM"

# Default suppresses Datadog logging; opt back in for end-to-end checks
./test-guard.sh --command "ksm secret get foo" --with-logging
```

PowerShell parameter form:

```powershell
.\test-guard.ps1
.\test-guard.ps1 -Command "az login"
.\test-guard.ps1 -Command "Get-AzVM" -WithLogging
```

The hook respects two env vars (used by the test harness; you should not need them in normal operation):

- `BASH_GUARD_NO_LOG=1` — skip the Datadog post.
- `BASH_GUARD_TEST_MODE=1` — write `<outcome>\t<pattern>` to stdout, suppress stderr, still set the exit code.

## Telemetry

On block or warn, the hook posts a structured log to Datadog via [`hooks/lib/datadog-log/`](../lib/datadog-log/README.md).

| Outcome | `status` | `event.name` | Tags |
|---------|----------|--------------|------|
| block   | `error`  | `hook_block` | `hook:bash-command-guard`, `outcome:block`, `reason:blocklist_match` |
| warn    | `warn`   | `hook_warn`  | `hook:bash-command-guard`, `outcome:warn`,  `reason:warnlist_match` |

Body fields:

- `message` — human-readable line with the matched pattern + a 200-char command preview.
- `source.tool` — always `Bash`.
- `source.command` — **the full command, not truncated**. This carries the data needed for triage; treat it as PII-equivalent for retention and access purposes.
- `source.matched_pattern` — the regex line that fired.

The shape mirrors `prompt-defender-pwsh` so a single `@event.name:hook_block` or `@event.name:hook_warn` query covers every hook in the plugin.

## Behaviour on errors

- Missing list file → that list is empty, no matches, no error.
- Bad regex line → the PowerShell side swallows the parse error in `try/catch`. The bash side emits a one-line parse error to stderr from the `[[ =~ ]]` builtin (no per-invocation redirect catches that — it's a parser-level diagnostic), then continues to the next pattern. The test matrix exercises every shipped pattern, so a bad line would be caught at dev time before merge.
- Empty / non-Bash payload → exit 0.
- Malformed JSON payload → fail-open (exit 0). Both runners cover this in `test-cases.json`.
- Missing Datadog token / network error → exit code unaffected.

The hook is fail-open: a broken hook never wedges Bash.
