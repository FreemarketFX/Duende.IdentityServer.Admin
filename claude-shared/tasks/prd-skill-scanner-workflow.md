# PRD: Skill Scanner GitHub Workflow

## Introduction

Add a GitHub Actions workflow that automatically scans all skill files in the repository using [cisco-ai-defense/skill-scanner](https://github.com/cisco-ai-defense/skill-scanner). This repository hosts all approved Claude Code skills for the organisation (both internal and third-party), so the workflow acts as a security gate — detecting prompt injection, data exfiltration, and malicious code patterns before they reach consumers. The build must fail if security issues are detected.

## Goals

- Automatically scan every skill file on PRs and pushes to main
- Block merges when security findings at medium severity or above are detected
- Surface findings as inline PR annotations via GitHub Code Scanning (SARIF)
- Also produce a human-readable summary in the workflow log for quick triage
- Require zero manual setup beyond repository secrets/permissions

## User Stories

### US-001: Create the skill-scanner workflow file
**Description:** As a repository maintainer, I want a GitHub Actions workflow that calls the `cisco-ai-defense/skill-scanner` reusable workflow so that all skills are scanned automatically.

**Acceptance Criteria:**
- [ ] Workflow file exists at `.github/workflows/scan-skills.yml`
- [ ] Workflow triggers on pull requests targeting `main`
- [ ] Workflow triggers on pushes to `main`
- [ ] Workflow can be triggered manually via `workflow_dispatch`
- [ ] Workflow calls the reusable workflow at `cisco-ai-defense/skill-scanner/.github/workflows/scan-skills.yml`
- [ ] Runs on `ubuntu-latest`
- [ ] Build passes
- [ ] Associated tests pass

### US-002: Configure scan policy and failure threshold
**Description:** As a security-conscious maintainer, I want the scanner configured with strict policy and medium+ severity threshold so that we catch the widest range of issues before skills reach consumers.

**Acceptance Criteria:**
- [ ] `policy` input set to `strict`
- [ ] `fail_on_severity` input set to `medium`
- [ ] `scan_mode` set to `scan-all` (scans the entire `skills/` directory)
- [ ] `skill_path` set to `skills/`
- [ ] Build fails when findings at medium severity or above are detected
- [ ] Build passes when no findings at medium+ severity exist
- [ ] Build passes
- [ ] Associated tests pass

### US-003: Enable SARIF upload and summary output
**Description:** As a PR reviewer, I want scan findings to appear both as inline PR annotations (via SARIF/Code Scanning) and as a human-readable summary in the workflow log so that I can triage quickly from either place.

**Acceptance Criteria:**
- [ ] SARIF scan job: `format` set to `sarif`, `upload_sarif` set to `true`
- [ ] Summary scan job: `format` set to `summary` (outputs to workflow log)
- [ ] Both jobs use the same `strict` policy and `medium` severity threshold
- [ ] Workflow has `security-events: write` permission for SARIF upload
- [ ] Workflow has `contents: read` permission for checkout
- [ ] Findings appear in the GitHub Code Scanning tab after a scan with results
- [ ] Summary output is visible in the workflow run log
- [ ] Build passes
- [ ] Associated tests pass

### US-004: Document the workflow in the repository
**Description:** As a contributor, I want a brief note in CLAUDE.md or the workflow file itself explaining the security gate so that I understand why my PR might be blocked.

**Acceptance Criteria:**
- [ ] Workflow file contains a top-level comment or description explaining its purpose
- [ ] CLAUDE.md updated with a section noting the skill-scanner security gate and what to do if a scan fails
- [ ] Build passes
- [ ] Associated tests pass

## Functional Requirements

- FR-1: The workflow must trigger on `pull_request` events targeting the `main` branch
- FR-2: The workflow must trigger on `push` events to the `main` branch
- FR-3: The workflow must support `workflow_dispatch` for manual runs
- FR-4: The workflow must call the reusable workflow at `cisco-ai-defense/skill-scanner/.github/workflows/scan-skills.yml`
- FR-5: The workflow must scan the `skills/` directory using `scan-all` mode with `--recursive` and `--check-overlap`
- FR-6: The workflow must use `strict` scan policy
- FR-7: The workflow must fail when findings at `medium` severity or above are detected
- FR-8: The workflow must output results in SARIF format and upload them to GitHub Code Scanning
- FR-9: The workflow must also produce a human-readable summary in the workflow log
- FR-10: The workflow must run on `ubuntu-latest`

## Non-Goals

- LLM-based semantic analysis is not enabled (requires API keys and adds cost/latency; can be added later)
- Behavioral dataflow analysis is not enabled in the initial version (can be opted in via `use_behavioral`)
- VirusTotal binary scanning is not enabled (no binaries in this repo — skills are markdown files)
- Custom policy YAML is not created; the built-in `strict` preset is used
- Pre-commit hook integration is out of scope (CI is the primary gate)

## Technical Considerations

- **Reusable workflow:** The `cisco-ai-defense/skill-scanner` repository publishes a reusable workflow at `.github/workflows/scan-skills.yml`. Calling it directly avoids duplicating installation and invocation logic, and automatically picks up scanner updates.
- **Version pinning:** Pin the reusable workflow to a release tag (e.g., `@v1`) rather than `@main` for stability. Update the pin when adopting new scanner versions.
- **Permissions:** The workflow needs `security-events: write` (for SARIF upload) and `contents: read` (for checkout). These must be declared at the job or workflow level.
- **Concurrency:** Consider adding a concurrency group to avoid redundant scans when a PR is updated rapidly.
- **Skill directory structure:** All skills live under `skills/{skill-name}/SKILL.md`. The scanner's `scan-all --recursive` mode will discover them automatically.
- **No secrets required initially:** Without LLM or VirusTotal analysis enabled, no API keys are needed. If LLM analysis is enabled later, `llm_api_key` must be added as a repository secret.

## Testing Strategy

- **Manual verification:** Create a test PR that adds or modifies a skill file and confirm the workflow triggers, scans, and reports results.
- **Negative test:** Introduce a deliberately suspicious pattern (e.g., a skill with an exfiltration-like instruction) in a branch and verify the build fails at medium severity.
- **SARIF verification:** Confirm findings appear in the GitHub Code Scanning tab after a scan that produces results.
- **Clean scan:** Verify the current `skills/` directory passes the strict/medium scan cleanly before merging the workflow (if it doesn't, address findings first or adjust the threshold).

## Success Metrics

- All PRs touching `skills/` are automatically scanned before merge
- Zero undetected malicious skill patterns reach the `main` branch (within scanner capabilities)
- Findings are visible as inline PR annotations, reducing review burden
- No false-positive rate high enough to cause developers to ignore or bypass the gate

## Open Questions

- What release tag should we pin the reusable workflow to? (Need to check latest stable release of `cisco-ai-defense/skill-scanner`)
- Should we also scan the `hooks/` directory, which contains PowerShell scripts? (The prompt-defender hook has its own patterns — skill-scanner may or may not handle `.ps1` files well)
- If the current skills produce false positives under `strict` policy, should we start with `balanced` and tighten later, or fix the findings first?
