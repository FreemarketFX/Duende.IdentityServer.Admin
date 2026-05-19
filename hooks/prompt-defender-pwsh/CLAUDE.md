# prompt-defender-pwsh — agent notes

## patterns.yaml is upstream — never edit it

`patterns.yaml` is mirrored from
`https://raw.githubusercontent.com/lasso-security/claude-hooks/refs/heads/dev/.claude/skills/prompt-injection-defender/patterns.yaml`.
Treat it as read-only. All organisation-specific patterns — including any
"conservative" / high-severity additions — go in `custom-patterns.yaml`. The
two files are merged at runtime by `Merge-Configs` in `post-tool-defender.ps1`,
so a custom pattern at any severity is fully equivalent to an upstream one.

If you find yourself reaching for `patterns.yaml`, stop and add to
`custom-patterns.yaml` instead.

## YAML duplicate-key trap

`powershell-yaml` (and YAML in general) rejects files where the same top-level
key appears twice. When adding a new pattern category, **append into the
existing category block** — do not start a second `rolePlayingPatterns:` /
`contextManipulationPatterns:` block lower in the file. Symptoms when you get
this wrong: `Exception calling "Load": "Duplicate key …"` from
`ConvertFrom-Yaml`, and `Load-Config` falling back to an empty hashtable so
**none of the custom patterns load** and the hook silently scans against
upstream-only.

Validate after editing:

```powershell
Import-Module powershell-yaml
$y = Get-Content custom-patterns.yaml -Raw | ConvertFrom-Yaml
$y.Keys                              # should have no duplicates
$y.contextManipulationPatterns.Count # > 0 means it loaded
```

## Detection structure (Scan-ForInjections)

Each detection is a hashtable with: `Category`, `Pattern`, `Reason`,
`Severity`, `Index`, `Length`. `Index`/`Length` are populated from
`[regex]::Match` and used by the Datadog telemetry path to build per-match
snippets — keep them populated if you refactor the scanner.

## Datadog telemetry contract

Logging happens in `Main` after detections fire, wrapped in its own
`try/catch` so a helper failure can never wedge the hook (mirrors
`hooks/elevation-guard/elevation-guard.ps1:60-70`). Severity → Datadog log
`status`:

| Detection severity | Datadog `status` |
|--------------------|------------------|
| `high`             | `error`          |
| `medium`           | `warn`           |
| `low`              | `info`           |

Driven by the **highest-severity detection in the batch** via `severityRank`.
If you add a new severity tier, update both the rank table and the switch.

Payload includes up to 5 snippets, each a 500-char window centred on the
match (`Index - 200`, length 500, clamped) with the head and tail replaced
by `[REDACTED]`. Only the match itself plus ~50 chars of immediate context
survives — far-edge neighbouring lines (which might carry unrelated
secrets) are dropped. Keep this redaction in place; if you change the
context width, document the new privacy posture.

## Test fixtures need binary content

The `test-files/datadog-monitoring.txt` fixture has to contain **real**
ESC bytes (`0x1B`) and Unicode Tag characters (U+E0000..U+E007F) for the
ANSI and ASCII-Smuggler patterns to fire. The Write tool sanitises both
out of normal text. Inject them via PowerShell after writing the rest:

```powershell
$esc = [char]0x1B
$content = $content -replace '<placeholder>', "${esc}[31m${esc}[1m${esc}[2J…"
[System.IO.File]::WriteAllText($path, $content,
    (New-Object System.Text.UTF8Encoding $false))
```

Verify with:

```powershell
[regex]::Match((Get-Content $path -Raw), '(\x1B\[[0-9;]*[A-Za-z]){3,}').Success
[regex]::Match((Get-Content $path -Raw), '(\uDB40[\uDC00-\uDC7F]){2,}').Success
```

## Test fixture / Write tool — `<function_calls>` collision

If you write a fixture that contains literal Anthropic tool-protocol XML
(`<function_calls>`, `<invoke>`, `</tool_use>` etc.), the **harness parser** —
not the Write tool — will treat your closing tags as the end of your own tool
call and truncate the content. Use a tag form that still matches the regex
but isn't a real harness opening (e.g. `<tool_use>…</tool_use>`).

The regex `(?i)<\/?(antml:)?(function_calls|tool_use|tool_result|invoke|parameter)\b`
matches any of these, so `<tool_use>` is sufficient to test the pattern.

## Benign false-positive guard

`test-files/benign-edge-cases.txt` is the regression net for false positives.
Every conservative pattern added to `custom-patterns.yaml` must either pass
the relevant benign sample or have a new benign sample added that proves the
phrasing it shouldn't fire on. Examples already covered:

- "DAN is the user's first name" — DAN-as-name, not the jailbreak
- "ignore previous warnings about deprecation" — "warnings" not in the
  alternation, so the override pattern correctly skips it
- "system prompt is set during initialisation" — not an extraction verb

## Plugin version bump on hook behaviour change

Hook behaviour changes (new patterns, new logging fields, scanner-shape
changes) need a patch bump in **both**:

- `.claude-plugin/plugin.json`
- `.claude-plugin/marketplace.json`

Without the bump, downstream caches won't refresh and consumers will keep
running the old defender. This is a stronger rule than just "skill changes" —
the upstream `CLAUDE.md` specifies skills, but the same cache mechanism
covers hooks.

## Local end-to-end smoke

Simulate a PostToolUse invocation without spinning up Claude:

```powershell
$payload = @{
  hook_event_name = 'PostToolUse'
  tool_name       = 'Read'
  tool_input      = @{ file_path = './test-files/datadog-monitoring.txt' }
  tool_response   = @{ content = (Get-Content ./test-files/datadog-monitoring.txt -Raw) }
  session_id      = 'local-smoke'
  cwd             = (Get-Location).Path
} | ConvertTo-Json -Depth 10 -Compress

$payload | pwsh -NoProfile -File ./post-tool-defender.ps1
```

Expect: a single-line JSON `{"decision":"block","reason":"…"}` on stdout,
exit 0. If `hooks/lib/datadog-log/client-token` exists locally the helper
will also POST a real log — fine for verification, but be aware you're
emitting test data to the EU tenant.

## Self-trigger carve-out

`Test-IsSelfReferencedPath` short-circuits scanning when the tool is reading
inside `$PSScriptRoot` (this hook's own directory). Without it, every
Read / Grep / Glob against the hook's source — `patterns.yaml`,
`custom-patterns.yaml`, fixtures, this CLAUDE.md, `post-tool-defender.ps1`
itself — fires high-severity warnings to the agent ("Anthropic
tool-protocol XML tags …") and pollutes Datadog with non-injection
traffic. Working *on* the hook is the common case where the patterns and
the content under review legitimately overlap.

Covered tools: `Read` (file_path), `Grep` (path), `Glob` (path).
**Not** covered: `Bash` — parsing arbitrary commands for paths is fragile,
so `cat ./patterns.yaml` from Bash will still trigger. Accept that and
prefer Read/Grep when working on the hook.

If you genuinely want to test the hook against its own source (e.g.
verifying a pattern in `custom-patterns.yaml` actually matches), use
`test-defender.ps1 -Test -File ./test-files/datadog-monitoring.txt` —
the `-Test` switch sets `PROMPT_DEFENDER_BYPASS_SELF_CHECK=1` for the
spawned child process so the full pipeline (incl. Datadog logging) runs
against the in-tree fixture. Outside of that harness, **do not set this
env var manually** — it disables the carve-out for the entire session.

## What this hook does NOT do

- It does **not** block tool calls. PostToolUse `decision: block` is a
  warning-to-Claude contract, not a hard block — the tool already ran.
- It does not redact tool output. Claude still sees the full content; the
  warning is appended in addition.
- It does not log the full transcript to Datadog. Only metadata + per-match
  500-char windows with `[REDACTED]` head/tail (~50 chars of context around
  the match survives). Widening the kept-context window needs a privacy
  review — it can pick up neighbouring lines from whatever file/output
  triggered the match.
