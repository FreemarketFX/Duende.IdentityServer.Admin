# CLAUDE.md

## Adding or Modifying Skills

When adding a new skill or modifying an existing one, you **must** update the plugin version in the same PR or consumers won't pick up the change:

1. **`.claude-plugin/plugin.json`** — bump `version` (semver: minor for new skills, patch for updates), add skill name to `keywords`, update `description`
2. **`.claude-plugin/marketplace.json`** — same fields: bump `version`, update `keywords`, update `description`

Both files must stay in sync. Without the version bump, the plugin cache on consumer machines won't refresh.

## Keeping README.md Up to Date

When adding or removing skills, hooks, scripts, CI workflows, or other top-level features, update `README.md` in the same PR:

- **Skills** — add/remove the row in the skills table
- **Hooks** — update the Hooks section
- **Scripts** — update the Scripts section
- **CI/CD workflows** — update the CI/CD section

## Cross-Monolith Skills

When creating a skill that will be run across multiple monoliths (e.g., SDK adoption, infrastructure migration, pattern enforcement):

1. **Audit every consuming monolith first.** Don't assume they share the same structure. Check at least: ClientActions, MoneyMovement, Organisation, ComplianceMonolith.
2. **Document variations.** Table format: what differs per monolith (schema names, column names, existing implementations, package versions, project structure).
3. **Build detection into the skill.** The skill should discover the current state (search for files, read schemas, check versions) rather than assuming a pattern. What's true in one monolith is often wrong in another.
4. **Test the skill's audit step mentally against each monolith.** Walk through the instructions with each repo's structure in mind — would the detection find the right files? Would the templates generate correct code?

## Hooks

When editing files under `hooks/<hook-name>/`, an autoloaded `CLAUDE.md` in that directory provides hook-specific guidance. For the `bash-command-guard` block/warn-list hook (DO-1316), see [`hooks/bash-command-guard/CLAUDE.md`](hooks/bash-command-guard/CLAUDE.md). For the `version-check` SessionStart staleness hook (DO-1318), see [`hooks/version-check/CLAUDE.md`](hooks/version-check/CLAUDE.md).

### Adding a new sh+cmd polyglot dispatcher

When adding a new `*.cmd` polyglot file (e.g. `hooks/<new-hook>/<new-hook>.cmd` modelled on `elevation-guard.cmd`), TWO settings must be configured or the hook will fail on Linux/macOS with `Permission denied`:

1. **`.gitattributes`** — pin LF line endings: `hooks/<new-hook>/<new-hook>.cmd text eol=lf`. POSIX `sh` requires LF for the `::CMDLITERAL` heredoc terminator. CRLF breaks the *nix branch silently.
2. **Git executable bit** — set `100755` so `/bin/sh` can dispatch the polyglot directly:
   ```sh
   git update-index --chmod=+x hooks/<new-hook>/<new-hook>.cmd
   git ls-files --stage hooks/<new-hook>/<new-hook>.cmd  # verify 100755 not 100644
   ```
   Without `+x`, every Linux/macOS consumer hits "Permission denied" the first time the hook fires — the cmd dispatcher works on Windows fine, so the bug is invisible to the author until a *nix user installs the plugin. Both DO-1316 (`bash-command-guard`) and DO-1318 (`version-check`) shipped without this and had to ship follow-up fixes; don't make it three.

## Agents

Shared subagents live at `.claude/agents/<name>.md`. They distribute the same way as scenario rules in `.claude/rules/` — pulled in via the git subtree, then referenced from consumer repos' `.claude/agents/`.

Each agent file uses YAML frontmatter:

```yaml
---
name: "agent-name"
description: "When to use. Examples: ..."
model: haiku|sonnet|opus
tools: Bash, Read, Grep, Glob
---
```

- **`tools`** — restrict to the minimum needed. Read-only analysis agents should list only `Bash, Read, Grep, Glob` so they cannot modify code or open PRs.
- **`model`** — `haiku` for mechanical work (log parsing, pattern matching), `sonnet` for judgment calls. Don't default to sonnet.
- Prefer pairing an agent with a thin **skill wrapper** at `skills/<name>/SKILL.md` that handles user interaction, file I/O, and approval gates. The agent does the heavy lifting in its own context window.

When adding a new agent, list it in the **Agents** table in `CLAUDE_TEMPLATE.md` so consumer repos pick it up via `/sync-claude-md`.

## Skill Structure

Each skill lives in `skills/{skill-name}/SKILL.md` with YAML frontmatter:

```yaml
---
name: skill-name
description: "What it does. Triggers on: keyword1, keyword2."
---
```

## Skill Scanner Security Gate

All skill files are automatically scanned for prompt injection, data exfiltration, and malicious patterns by the [cisco-ai-defense/skill-scanner](https://github.com/cisco-ai-defense/skill-scanner) GitHub Actions workflow (`.github/workflows/skill-scanner.yml`), which calls the reusable workflow from `gha-shared-workflows`.

- **When it runs:** on every PR targeting `main`, every push to `main`, and on-demand via `workflow_dispatch`.
- **Policy:** `strict` — catches the widest range of issues.
- **Threshold:** `info` — the build fails on any finding (lowest severity included).

### If a scan fails your PR

1. Check the **Security** tab or PR annotations for the specific findings.
2. Review the flagged skill file and remove or refactor the problematic pattern.
3. Push a fix — the scan re-runs automatically on the updated PR.
4. If you believe the finding is a false positive, note it in the PR description and request a review from a maintainer.

## Commit Format

```
type(TICKET): Short description

Longer description if needed.
```

Types: `feat`, `fix`, `chore`, `refactor`, `docs`
