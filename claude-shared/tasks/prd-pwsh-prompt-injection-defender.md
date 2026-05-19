# PRD: PowerShell Prompt Injection Defender Hook

## Introduction

Port the existing Python-based Claude Code PostToolUse prompt injection defender to PowerShell, providing a native Windows alternative that maintains full compatibility with the shared `patterns.yaml` configuration. The PowerShell version will detect the same prompt injection patterns (instruction overrides, role-playing/DAN, encoding/obfuscation, context manipulation) in tool outputs and warn Claude accordingly.

## Goals

- Provide a PowerShell-native PostToolUse hook that mirrors the Python defender's behavior exactly
- Use the `powershell-yaml` module for clean YAML parsing of the shared `patterns.yaml`
- Port the interactive test suite to PowerShell for validation
- Maintain identical JSON I/O contract (stdin input, stdout JSON output, exit code 0)
- Share the same `patterns.yaml` config file — no pattern duplication

## User Stories

### US-001: Create PowerShell PostToolUse defender script
**Description:** As a Windows developer using Claude Code, I want a PowerShell prompt injection defender hook so that I don't need Python/uv installed to protect against prompt injection in tool outputs.

**Acceptance Criteria:**
- [ ] `post-tool-defender.ps1` reads JSON from stdin with `tool_name`, `tool_input`, and `tool_response` fields
- [ ] Loads patterns from `patterns.yaml` using `powershell-yaml` module (`ConvertFrom-Yaml`)
- [ ] Searches for `patterns.yaml` in the same 3-location priority order as the Python version: script directory, `../patterns.yaml` (hooks/ sibling), `$env:CLAUDE_PROJECT_DIR/.claude/hooks/prompt-injection-defender/patterns.yaml`
- [ ] Scans extracted text against all 4 pattern categories using .NET regex with `IgnoreCase` and `Multiline` options
- [ ] Outputs `{"decision":"block","reason":"..."}` JSON to stdout when detections are found
- [ ] Outputs nothing and exits 0 when no detections are found
- [ ] Fails open (exit 0, no output) on any error (missing YAML module, bad input, etc.)
- [ ] Build passes
- [ ] Associated tests pass

### US-002: Implement text extraction for all tool output formats
**Description:** As the defender hook, I need to extract text content from various tool result formats so that all monitored tool outputs are scanned consistently.

**Acceptance Criteria:**
- [ ] Handles string results directly
- [ ] Extracts from dict fields: `content`, `output`, `result`, `text`, `file_content`, `stdout`, `data`
- [ ] Handles content arrays (list of content blocks with `text` fields)
- [ ] Handles nested `file.content` structure (Read tool)
- [ ] Falls back to JSON serialization of the entire object
- [ ] Handles list results by recursively extracting and joining
- [ ] Returns empty string for null/missing results
- [ ] Build passes
- [ ] Associated tests pass

### US-003: Implement source info extraction and warning formatting
**Description:** As Claude receiving a warning, I need clear source information and severity-grouped detections so I can assess the threat appropriately.

**Acceptance Criteria:**
- [ ] Extracts source info per tool type: Read (file_path), WebFetch (url), Bash (command, truncated at 60 chars), Grep (pattern + path), Glob (pattern), Task (description, first 40 chars), MCP tools (tool name)
- [ ] Groups detections by severity: HIGH, MEDIUM, LOW
- [ ] Warning format matches Python version exactly (separator lines, header, severity sections, recommended actions)
- [ ] Build passes
- [ ] Associated tests pass

### US-004: Port the interactive test suite to PowerShell
**Description:** As a developer maintaining the defender, I want a PowerShell test script so I can validate pattern detection without switching to Python.

**Acceptance Criteria:**
- [ ] `test-defender.ps1` provides interactive mode, file testing, direct text testing, and sample batch testing
- [ ] Contains the same sample injection texts across all 5 categories (instruction_override, role_playing_dan, encoding_obfuscation, context_manipulation, benign)
- [ ] Reports detection accuracy as pass/fail with percentage summary
- [ ] Shows false negatives and false positives
- [ ] Supports `-Interactive`, `-File <path>`, `-Text <string>`, `-Samples`, `-Verbose` parameters
- [ ] Build passes
- [ ] Associated tests pass

## Functional Requirements

- FR-1: `post-tool-defender.ps1` must accept JSON on stdin matching the Claude Code PostToolUse hook contract: `{"tool_name":"...", "tool_input":{...}, "tool_response":...}`
- FR-2: Must monitor the same tool set: Read, WebFetch, Bash, Grep, Glob, Task, and any tool with `mcp__` or `mcp_` prefix
- FR-3: Must skip scanning for non-monitored tools (exit 0 silently)
- FR-4: Must skip scanning when extracted text is empty or fewer than 10 characters
- FR-5: Must use .NET `[regex]::Match()` with `IgnoreCase -bor Multiline` flags for pattern matching
- FR-6: Must output valid JSON to stdout only when detections are found
- FR-7: Must always exit with code 0 (fail-open design)
- FR-8: Must load `powershell-yaml` module; if unavailable, fail open with no output
- FR-9: `test-defender.ps1` must import functions from `post-tool-defender.ps1` via dot-sourcing or module import
- FR-10: Both scripts must live in `hooks/defender-pwsh/`

## Non-Goals

- No settings.json generation — users configure hooks themselves
- No cross-platform OS detection or Python/PowerShell switching logic
- No modification to the existing Python scripts
- No changes to `patterns.yaml` format or content
- No PowerShell module packaging (`.psd1`/`.psm1`) — keep as standalone scripts
- No PreToolUse hook — this is PostToolUse only

## Technical Considerations

- **YAML Parsing:** Use `powershell-yaml` module (`Install-Module powershell-yaml`). The `ConvertFrom-Yaml` cmdlet returns PowerShell hashtables/arrays that map cleanly to the Python dict/list structures.
- **Regex Engine:** .NET regex (`[System.Text.RegularExpressions.Regex]`) is PCRE-compatible but not identical to Python `re`. Key differences to watch:
  - Named groups syntax differs but is not used in `patterns.yaml`
  - Unicode character classes (`\u200B` etc.) work the same way
  - Use `[regex]::new($pattern, 'IgnoreCase,Multiline')` for compiled patterns
  - Wrap in try/catch to skip invalid patterns (same as Python)
- **stdin Reading:** Use `[Console]::In.ReadToEnd()` or `$input | Out-String` to read piped JSON
- **JSON Handling:** Use `ConvertFrom-Json` (input) and `ConvertTo-Json -Compress` (output) — both are built-in
- **Path Resolution:** Use `$PSScriptRoot` for script directory (equivalent to Python's `Path(__file__).parent`)
- **Error Handling:** Wrap all operations in try/catch, always exit 0. Use `$ErrorActionPreference = 'Stop'` inside try blocks for consistent error trapping.
- **Performance:** The 5-second timeout in hook config is generous. PowerShell cold start is slower than Python but pattern matching against ~80 regexes should complete well within budget.

## Testing Strategy

- **Manual testing:** Use `test-defender.ps1 -Samples` to run the same battery of injection samples as the Python version and compare accuracy
- **Interactive testing:** `test-defender.ps1 -Interactive` for ad-hoc pattern testing
- **Cross-validation:** Run both Python and PowerShell test suites against the same `patterns.yaml` and compare results — they should be identical
- **Edge cases to verify:**
  - Empty/null stdin → exit 0 silently
  - Malformed JSON stdin → exit 0 silently
  - Missing `powershell-yaml` module → exit 0 silently
  - Unicode patterns (zero-width chars, Cyrillic/Greek homoglyphs) match correctly in .NET regex
  - Very large tool output (100KB+) completes within timeout

## Success Metrics

- PowerShell defender produces identical detection results as Python version for all sample texts
- Hook executes within the 5-second timeout on cold start
- Zero false positive difference between Python and PowerShell versions against the same input
- Can be configured as a Claude Code PostToolUse hook on Windows without Python installed

## Open Questions

- Should the `powershell-yaml` module be auto-installed if missing, or just fail open with a stderr warning?
- Are there any `patterns.yaml` regex features that behave differently in .NET vs Python `re` that need pattern adjustments?
