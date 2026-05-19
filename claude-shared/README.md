#   CLAUDE-SHARED
[![Skill Scanner](https://github.com/FreemarketFX/claude-shared/actions/workflows/skill-scanner.yml/badge.svg)](https://github.com/FreemarketFX/claude-shared/actions/workflows/skill-scanner.yml)
[![Build Sandbox Image](https://github.com/FreemarketFX/claude-shared/actions/workflows/build-sandbox-image.yml/badge.svg)](https://github.com/FreemarketFX/claude-shared/actions/workflows/build-sandbox-image.yml)

> [!WARNING]
> **DO NOT MODIFY THE CONTENTS OF THIS FOLDER OUTSIDE OF THE CLAUDE-SHARED GIT REPOSITORY**
>

Shared Claude Code skills, scripts, and templates.

## Installing claude-shared

Run the following command from the root of a git repository to add the `claude-shared` repository as a subtree
```shell
git subtree add --prefix=claude-shared https://github.com/FreemarketFX/claude-shared.git main --squash -m "feat(FMFX-13816): Adding claude-shared subtree"
```

## Updating claude-shared

Run the following script from any consuming repository to update the `claude-shared` git subtree

```powershell
.\claude-shared\update-claude-shared.ps1

# Or pull from a specific branch
.\claude-shared\update-claude-shared.ps1 -Branch feature-branch-name
```

## Skills

Skills are invoked via `/skillname` in Claude Code.

| Skill | Trigger | Description |
|-------|---------|-------------|
| `/adopt-user-roles-sdk` | "adopt user roles sdk", "wire up user roles" | Adopt the PlatformCode UserRolesGrantHandler SDK — scaffolds IRolePermissionProvider, wires DI, adds subscription, migrates grants table |
| `/adr` | "create adr", "architecture decision" | Create an Architecture Decision Record (ADR) with structured options analysis |
| `/architecture-test` | "architecture test", "module isolation" | Scaffold module dependency isolation tests using NetArchTest with assembly markers |
| `/bdd-test` | "create bdd test", "add unit test" | Scaffold a BDD unit test with specs and steps |
| `/brighter-event` | "create brighter event", "add message event" | Create a Brighter event with mapper and handler for cross-service messaging via message bus |
| `/conversation-recall` | "recall conversation", "what did we discuss", "search history" | Search, summarize, and learn from past Claude Code sessions on disk. Quick mode greps the prompt index and returns cached summaries; deep mode fans out Haiku agents for multi-session digests and can promote learnings into `MEMORY.md` |
| `/domain-event` | "create domain event", "add domain event" | Create a domain event and handler for intra-aggregate events within the domain layer |
| `/feature` | "create feature", "new endpoint", "scaffold command" | Scaffold a command endpoint with handler, validator, and DTOs for POST/PUT/DELETE operations |
| `/freemarket-openapi` | "ClientActions create beneficiary", "MoneyMovementApi quote", "Platform users list" | Look up Freemarket API endpoints from `design/openapi-specs/{Name}Api_internal.json` for HTML/UI prototyping — no cached copy |
| `/handover` | "handover", "hand off to next session", "create a handover", "wrap up for next agent" | Compact the current conversation into a handover-{description}.md in the OS temp dir — decisions, state, open questions, and next-step suggestions, without duplicating PRDs/ADRs/code |
| `/infrastructure-update` | "update bootstrap", "update bicep", "add container" | Update bootstrap, bicep, and permissions after adding a Cosmos container, SQL schema, or permission scheme |
| `/integration-test` | "create integration test", "test endpoint" | Scaffold an API integration test with specs and steps (required for new endpoints) |
| `/jira-csv` | "jira csv", "create jira stories", "export to jira" | Generate Jira stories from source material (PRDs, specs, pasted text, URLs) and output a Jira Cloud CSV import file |
| `/post-ralph` | "post ralph", "archive ralph", "ralph cleanup" | Archive a completed Ralph run and commit artifacts |
| `/unarchive-prd` | "unarchive prd", "restore prd", "resume ralph" | Restore archived prd.json and progress.txt back to tasks/current/ for another Ralph run |
| `/open-pr` | "open pr", "create pr", "raise pr", "ship this", "push for review" | Walk from a ready branch to an open PR — hard gates (`tasks/current/`, ralph artifacts, diff-stat noise, drive-by paths), pre-PR skills checklist, commit-strategy selection, standardized FMFX description (Summary / Test plan / Risk Assessment), Conventional Commits + Co-Authored-By trailer, draft PR by default |
| `/plan-ticket` | "create a ticket", "turn plan into ticket", "generate acceptance criteria" | Generate a Jira ticket (title, description, acceptance criteria) from the current Claude Code plan |
| `/pr-build-doctor` | "pr build doctor", "fix ci", "why is the build failing" | Watch a PR build, diagnose failures, fetch failed logs, and walk through fixes |
| `/pr-feedback` | "pr feedback", "address pr feedback" | Extract actionable PR comments and update PRD with required changes for Ralph |
| `/prd` | "create a prd", "plan this feature" | Generate a structured PRD with clarifying questions, user stories, and acceptance criteria |
| `/query` | "create query", "new get endpoint", "scaffold query" | Scaffold a query endpoint with handler and response for GET operations |
| `/question-me` | "quiz me", "grill me", "question me", "challenge my design" | Relentlessly interview you about a plan or design, resolving every decision branch, producing a decision log for PRD input |
| `/ralph` | "convert this prd", "ralph json" | Convert PRDs to `prd.json` format for the Ralph autonomous agent; final step re-validates the generated stories against the source PRD via the `ralph-prd-validator` subagent and ships a `prd-validation.md` report |
| `/ralph-log-doctor` | "ralph log doctor", "ralph postmortem", "why did ralph fail" | Postmortem analysis of a `ralph-sandbox.log` run — classifies recurring failures and emits a punch list of fixes routed to claude-shared/ vs the target repo |
| `/risk` | "assess risk", "evaluate pr risk" | 8-question risk assessment across 4 dimensions (customer, system, data, operational) |
| `/security-champion` | "security review", "is this code safe", "threat model", "check my Bicep" | Conversational, full-scope security review with STRIDE threat modelling, OWASP checklists, CWE tagging, and actionable remediation code. For branch-diff-only review, prefer the built-in `/security-review`. |
| `/self-code-review` | "review code", "review my changes", "staff review" | Review branch changes against main as a principal/staff engineer — correctness, architecture, security, maintainability |
| `/stylecop-precheck` | "stylecop precheck", "check stylecop", "analyzer check" | Audit C# files for common StyleCop/analyzer violations before building (SA1202, SA1413, IDE1006, etc.) |
| `/sync-claude-md` | "sync claude", "sync template" | Compare repo CLAUDE.md against the shared template, show missing items for selection, commit and create PR |
| `/test-sonar` | "test coverage", "test gaps", "edge cases" | Semantic test coverage analysis beyond line metrics — finds gaps, generates adversarial tests, scores confidence |
| `/ticket-validation` | "validate ticket", "check requirements" | Validate a work item against the codebase — checks validation rules, permissions, invariants, events, API contract, persistence, and testing gaps |
| `/tool-security-analysis` | "propose a tool", "tool approval", "analyse mcp", "security review of", "adoption record", "infosec review" | Two modes for the FMFX Tool Approval Process. **Requester:** paste-ready Jira approval ticket. **InfoSec:** Confluence adoption record + git-tracked JSON snapshot in `tool-adoption-records/<slug>/`, plus a per-slug `CLAUDE.md` (determinism contract — re-runs reproduce) and `settings.json` (managed allow/deny). Semantic diff vs prior snapshot, reviewer-feedback loop with verbatim log, and explicit commit-approval gate |

## Agents

Specialised subagents distributed via `.claude/agents/<name>.md` (same path-pattern as scenario rules). Spawned by skills via the Agent tool; not directly invocable as `/agent-name`.

| Agent | Used by | Purpose |
|-------|---------|---------|
| `ralph-log-doctor` | `/ralph-log-doctor` skill | Read-only postmortem analyst for ralph-sandbox runs |
| `ralph-prd-validator` | `/ralph` skill | Read-only coverage analyst — maps every source-PRD requirement to a covering user story / AC bullet before commit |
| `http-response-test-audit` | Direct (Agent tool) | Read-only auditor — groups HTTP integration tests by `VERB route-template`, flags endpoints with no full-response-shape assertion (status-only / single-field / partial body). Honours 204-exempt and `ProblemDetails`-as-full-shape rules. `SCOPE=diff` (default) or `all` |

## Scripts

### Start-DevTerminal (`start-devterminal.ps1`)

Launches Windows Terminal with a 2-pane dev layout: Claude Code (Docker Sandbox) on the left and PowerShell on the right.

**Features:**
- Auto-named tab titles per project (e.g. `PlatformCode - Claude`, `PlatformCode - Ralph`)
- Color-coded tab backgrounds per monolith — visually distinguish which repo you're in at a glance
  - PlatformCode: blue, ClientActions: teal, MoneyMovement: amber, Organisation: purple, ComplianceMonolith: red, claude-shared: green

**Setup:** Copy the script one folder above `claude-shared` (e.g. `C:\dev\freemarket\`):

```powershell
Copy-Item .\start-devterminal.ps1 ..
```

**Usage:**

```powershell
# From C:\dev\freemarket\, pass a project folder name:
.\start-devterminal.ps1 PlatformCode

# Or pass a full path:
.\start-devterminal.ps1 C:\other\path
```

### Status Line (`scripts/statusline-command.sh`)

Displays a rich status bar in Claude Code with directory, git info, model, context usage, and token usage — all with a green-to-red gradient.

```
📁 C:\dev\project | 🌿 main ✏️3 📦1 🕐2h ↑2 | 🤖 Opus | 📊 ctx ██░░░░░░░░ 25% | 🔥 51k ██░░░░░░░░ 25%
```

**Features:**
- 📁 Current directory
- 🌿 Branch, ✏️ dirty files, 📦 stashes, 🕐 last commit age, ↑↓ ahead/behind
- ⚠️ Rebase/merge/cherry-pick state, ❌ color-coded conflict severity (yellow 1, orange 2-3, red 4+)
- 🤖 Model name + Ralph progress (e.g. `🤖 Ralph 3/7`)
- 📊 Context window usage (gradient bar)
- 🔥 Total token usage (gradient bar)

**Install:**

```bash
cp scripts/statusline-command.sh ~/.claude/statusline-command.sh
```

Add to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/statusline-command.sh"
  }
}
```

> **Note:** Requires PowerShell (used for JSON parsing instead of `jq`).

### Session Summary (`scripts/session-summary.sh`)

Prints a quick recap of git activity — commits made, files changed, branch status, and stashes. Useful at the end of a Claude Code session to see what was accomplished.

```
📋 Session Summary (last 480m)
──────────────────────────────────────────────────

📝 Commits: 3
   • abc1234 feat: add new endpoint
   • def5678 fix: validation bug
   • ghi9012 chore: update deps

📂 Working Tree
   Modified:  2
   Staged:    0
   Untracked: 1

🌿 main ↑1 unpushed
```

**Usage:**

```bash
# Default: last 8 hours
bash scripts/session-summary.sh

# Custom: last 2 hours
bash scripts/session-summary.sh 120
```

### Ralph Sandbox (`ralph-sandbox/`)

Ralph is an autonomous coding agent that runs Claude Code inside a Docker sandbox to implement features from a PRD. See the full [Ralph Sandbox README](ralph-sandbox/README.md) for prerequisites, setup, and detailed usage.

**Quick usage:**
```powershell
.\claude-shared\ralph-sandbox\ralph-sandbox.ps1 -MaxIterations 10
```

**Local image build:**
```powershell
ralph-sandbox/docker/build-local.ps1
```
This pulls the base image, builds `ralph-sandbox:latest` and a digest-tagged variant locally (no push).

**Workflow:** `/prd` (write PRD) → `/ralph` (convert to prd.json) → run Ralph

### Sandbox Doctor (`ralph-sandbox/sandbox-doctor.ps1`)

Pre-flight health check for Ralph sandbox runs. Validates Docker, line endings, disk space, NuGet config, credentials, and stale artifacts.

**Usage:**

```powershell
.\claude-shared\ralph-sandbox\sandbox-doctor.ps1        # Report only
.\claude-shared\ralph-sandbox\sandbox-doctor.ps1 -Fix   # Auto-remediate fixable issues
```

## Tearing down Sandbox Containers

Sandbox containers persist and must be destroyed when you're finished building a feature within a repository. If you want a completely clean environment, you can simply run `docker sandbox reset` and this will remove **ALL** sandbox containers and images.

If you only want to remove the sandbox container for the current repository, run the following script from within the repository.

```powershell
.\claude-shared\ralph-sandbox\sandbox-teardown.ps1
```

## Hooks

The `hooks/` directory contains hook scripts that can be wired into Claude Code via `settings.json`.

- **`prompt-defender-pwsh`** — a post-tool hook that scans tool outputs for prompt injection patterns. See [`hooks/prompt-defender-pwsh/README.md`](hooks/prompt-defender-pwsh/README.md) for setup.
- **`elevation-guard`** — a `PreToolUse` hook that blocks every tool call when Claude Code is running with elevated OS privileges (Windows Administrator / Unix root). On block it emits a human-readable line plus a `CLAUDE_ELEVATION_BLOCK …` sentinel to stderr (captured in OTEL hook telemetry), exits 2, and additionally posts a structured log to Datadog via the shared helper at [`hooks/lib/datadog-log/`](hooks/lib/datadog-log/README.md). Implemented as a single sh+cmd polyglot dispatcher that runs natively under `cmd.exe` on Windows and `bash` on \*nix; no `pwsh` and no `node` dependency. See [`hooks/elevation-guard/README.md`](hooks/elevation-guard/README.md).
- **`bash-command-guard`** — a `PreToolUse` hook (matcher: `Bash`) that inspects every Bash command against two regex lists. The block list (`blocklist.txt`) blocks Azure CLI / `Verb-Az*` PowerShell cmdlets / Azure REST hostnames / common credential-harvesting commands and file paths (`~/.ssh/id_*`, `~/.aws/credentials`, `gh auth token`, `op read`, etc.). The warn list (`warnlist.txt`) logs to Datadog without blocking — used to trial new restrictions. Datadog telemetry is shape-aligned with `prompt-defender-pwsh`: `event.name` is `hook_block` (status `error`) or `hook_warn` (status `warn`), and `source.command` carries the full command for triage. Both lists are user-editable, ship in-repo, and are covered by a `test-cases.json`-driven test harness (`test-guard.sh` / `test-guard.ps1`). See [`hooks/bash-command-guard/README.md`](hooks/bash-command-guard/README.md).
- **`version-check`** — a `SessionStart` hook that compares the installed plugin version against `main` and, when stale, surfaces a one-line `additionalContext` upgrade prompt to Claude (`/plugin update freemarket-claude-skills`). Fetches the upstream version via `gh api` so it works against the private source repo using the user's existing `gh auth login` token. If `gh` isn't on PATH, surfaces a once-per-hour install-gh prompt and logs `outcome=gh_missing` to Datadog so we can track misconfigured clients. Network calls are rate-limited to once per hour per machine via a `$TEMP`/`$TMPDIR` cache (15-min negative cache for transient failures); fail-open, never blocks startup. Same sh+cmd polyglot pattern as `elevation-guard`; emits Datadog telemetry via the shared helper. See [`hooks/version-check/README.md`](hooks/version-check/README.md).
- **`lib/datadog-log`** — shared library any hook can source to emit a structured log to Datadog when it blocks/warns. Exposes `Send-DatadogHookLog` (PowerShell) and `send_datadog_hook_log` (bash); authenticated by a bundled Datadog **Client Token** (write-only, log-spam-only blast radius, rotation runbook in the helper README). See [`hooks/lib/datadog-log/README.md`](hooks/lib/datadog-log/README.md).
- **`freemarket-monolith-hooks`** — bundle of 12 `PreToolUse` and `PostToolUse` hooks enforcing modular-monolith codebase invariants and personal-workflow guardrails (e.g. ban `dynamic` in tests, force `When` step in BDD, block `gh pr create` when `tasks/current/` is in the branch diff, force `/pr-build-doctor` after push). All hooks self-scope by file glob or command shape, so installation is a no-op in microservice repos. See [`hooks/freemarket-monolith-hooks/README.md`](hooks/freemarket-monolith-hooks/README.md).

## CI/CD

### Notify Consuming Repos (`.github/workflows/notify-consumers.yml`)

Automatically dispatches a `claude-shared-updated` event to all repos that consume `claude-shared` whenever changes are pushed to `main`. This triggers those repos to pull the latest subtree updates.

- Uses `gh search code` to dynamically discover consuming repos (those with an `update-claude-shared.yml` workflow)
- Generates a scoped GitHub App token limited to only the discovered repos for dispatch
- Can also be triggered manually via `workflow_dispatch`

### Skill Scanner (`.github/workflows/skill-scanner.yml`)

Scans all skill files for prompt injection, data exfiltration, and malicious patterns using [cisco-ai-defense/skill-scanner](https://github.com/cisco-ai-defense/skill-scanner).

- Runs on every PR targeting `main`, every push to `main`, and on-demand via `workflow_dispatch`
- Policy: `strict` — threshold: `medium` (build fails on medium severity or above)

### Build Sandbox Image (`.github/workflows/build-sandbox-image.yml`)

Builds and pushes the Ralph sandbox Docker image to Azure Container Registry so that local sandbox runs pull a pre-built image instead of building from scratch.

### Receiving updates in consuming repos

For a repo to receive automatic updates, it must have a caller workflow at `.github/workflows/update-claude-shared.yml` that:

1. Listens for the `repository_dispatch` event with type `claude-shared-updated`
2. Calls the shared workflow from `gha-shared-workflows` which runs `git subtree pull`

Create this file in your repo:

```yaml
name: Update claude-shared

permissions:
  contents: read

on:
  workflow_dispatch:
  repository_dispatch:
    types: [claude-shared-updated]
  schedule:
    - cron: "0 7 * * 1-5"

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  update-claude-shared:
    permissions:
      contents: write
      actions: read
    uses: FreemarketFX/gha-shared-workflows/.github/workflows/update-claude-shared.yml@main
    secrets: inherit
```

This gives you three update paths:
- **Automatic** — triggered immediately when `claude-shared` pushes to `main`
- **Scheduled** — daily fallback (weekdays at 7am) in case a dispatch is missed
- **Manual** — via `workflow_dispatch` for on-demand pulls

## Templates

| File | Purpose |
|------|---------|
| `CLAUDE_TEMPLATE.md` | Base template for project CLAUDE.md files — commands, skills index, rules index, architecture overview, code style, NEVER-do list |

## Rules

Scenario-specific guidance lives under `.claude/rules/` and is referenced from `CLAUDE_TEMPLATE.md` via `@`-imports. Each rule file scopes to a specific area so it's only loaded when relevant.

| Rule | Applies When |
|------|--------------|
| `endpoints.md` | Editing `*.Endpoint.cs`, `*.Handler.cs`, command/query handlers (Result Types, HATEOAS, permissions, double Cosmos read avoidance) |
| `domain.md` | Working in `src/*/Domain/` (aggregates, MaybeAggregate, value objects) |
| `events.md` | Creating or modifying domain / Brighter events |
| `change-feed.md` | Read-model handlers on the Cosmos change-feed path (idempotency) |
| `validators.md` | Editing `*.Validator.cs` (null safety, deduplication) |
| `sql.md` | Editing `*.sql` or code that executes SQL (queries + migration conventions) |
| `testing.md` | Anything under `test/` (BDD, doubles, gotchas, auth tests, shared infra, integration DTOs) |
| `infrastructure.md` | Bicep / Cosmos containers / `.json` edits |
| `pull-requests.md` | Commit format and PR creation hygiene |

## Installation

### Option 1: Plugin (Recommended)

**From GitHub:**

```
/plugin marketplace add FreemarketFX/claude-shared
/plugin install freemarket-claude-skills@freemarket-tools
```

**From local path:**

```
/plugin marketplace add /path/to/claude-shared
/plugin install freemarket-claude-skills@freemarket-tools
```

### Option 2: Claude Code Settings

Add skills to your Claude Code settings file (`~/.claude/settings.json`):

```json
{
  "skills": [
    "C:/path/to/claude-shared/skills/prd",
    "C:/path/to/claude-shared/skills/ralph",
    "C:/path/to/claude-shared/skills/risk",
    "C:/path/to/claude-shared/skills/pr-feedback"
  ]
}
```

Or add project-specific skills in `.claude/settings.json` in your repo:

```json
{
  "skills": [
    "../claude-shared/skills/prd",
    "../claude-shared/skills/ralph",
    "../claude-shared/skills/risk",
    "../claude-shared/skills/pr-feedback"
  ]
}
```

### Option 3: Symlinks

Symlink skills to your Claude Code skills directory:

```powershell
# Windows
mklink /D "$env:USERPROFILE\.claude\skills\prd" "C:\path\to\claude-shared\skills\prd"
mklink /D "$env:USERPROFILE\.claude\skills\ralph" "C:\path\to\claude-shared\skills\ralph"
mklink /D "$env:USERPROFILE\.claude\skills\risk" "C:\path\to\claude-shared\skills\risk"
mklink /D "$env:USERPROFILE\.claude\skills\pr-feedback" "C:\path\to\claude-shared\skills\pr-feedback"
```

```bash
# macOS/Linux
ln -s /path/to/claude-shared/skills/prd ~/.claude/skills/prd
ln -s /path/to/claude-shared/skills/ralph ~/.claude/skills/ralph
ln -s /path/to/claude-shared/skills/risk ~/.claude/skills/risk
ln -s /path/to/claude-shared/skills/pr-feedback ~/.claude/skills/pr-feedback
```
