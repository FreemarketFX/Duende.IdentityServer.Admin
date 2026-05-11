# PRD: Ralph Sandbox Improvements

## Introduction

Ralph sandbox iterations are significantly wasteful. In the most recent run (MoneyMovement FMFX-14939), only ~5.5/10 iterations were productive: 3 were OOM-killed during `dotnet build`, 1 was blocked by a dirty working tree left by a killed iteration, and 69/147 tests failed because MCR container registry is blocked by the network policy. This PRD addresses all three root causes.

## Goals

- Unblock TestContainers by allowing MCR hosts through the network policy
- Automatically recover from killed iterations (stash, log, retry)
- Give the agent a build strategy that avoids OOM from `cp -r`
- Increase productive iteration ratio from ~55% to ~90%+

## User Stories

### US-001: Add MCR to network policy allow-list
**Description:** As an operator, I want MCR hosts allowed through the sandbox network policy so that TestContainers can pull SQL Server and Cosmos DB images.

**Acceptance Criteria:**
- [ ] `mcr.microsoft.com` and `*.mcr.microsoft.com` added to `--allow-host` list in `ralph-sandbox.ps1`
- [ ] README.md network policy documentation updated to include MCR hosts
- [ ] Build passes (script syntax valid — no PowerShell parse errors)

### US-002: Detect killed iterations and auto-recover
**Description:** As an operator, I want the orchestrator to detect when an iteration was killed (OOM/exit 137), auto-stash dirty state, log the kill to progress.txt, and retry the iteration so that no iterations are wasted.

**Acceptance Criteria:**
- [ ] After `docker sandbox run` try/catch, detect killed iterations by checking output for absence of `"type":"result"`
- [ ] On kill detection: run `docker sandbox exec` to `git stash --include-untracked -m 'ralph: auto-stash after killed iteration'` inside the sandbox
- [ ] On kill detection: append a timestamped entry to progress.txt noting the killed iteration number
- [ ] On kill detection: decrement the iteration counter (`$i--`) so the killed iteration is retried
- [ ] Toast notification updated to indicate "killed + retrying" when a kill is detected
- [ ] Build passes (script syntax valid)

### US-003: Replace hard STOP rule with recovery instructions in CLAUDE.md
**Description:** As a Ralph agent, I need instructions on how to handle leftover changes from killed iterations instead of hard-stopping, so I can recover and continue working.

**Acceptance Criteria:**
- [ ] Phase 1 step 4 rewritten: instead of "STOP", instruct agent to inspect uncommitted changes, attempt `git stash pop`, and `git stash drop` if it fails (discard killed work)
- [ ] Instructions are clear and unambiguous for an AI agent
- [ ] Build passes

### US-004: Add Build Strategy section to CLAUDE.md
**Description:** As a Ralph agent, I need guidance on build strategy to avoid OOM kills from copying the entire repo.

**Acceptance Criteria:**
- [ ] New "Build Strategy" section added to CLAUDE.md (after Line Ending Discipline or similar)
- [ ] Documents: try building in-place first
- [ ] Documents: if virtiofs fails (MSB3248), use `rsync --exclude='.git' --exclude='bin' --exclude='obj'` instead of `cp -r`
- [ ] Documents: never `cp -r` the entire repo (causes OOM)
- [ ] Documents: tests need MCR network access for SQL Server / Cosmos images via TestContainers
- [ ] Build passes

## Functional Requirements

- FR-1: Add `--allow-host "mcr.microsoft.com"` and `--allow-host "*.mcr.microsoft.com"` to the network proxy command in `ralph-sandbox.ps1`
- FR-2: After the `docker sandbox run` try/catch block, check `$IterationOutput` for presence of a `"type":"result"` line. If absent, treat the iteration as killed.
- FR-3: On kill detection, execute `docker sandbox exec $sandboxName bash -c "cd <repo-path> && git stash --include-untracked -m 'ralph: auto-stash after killed iteration'"` to clean the working tree
- FR-4: On kill detection, append a log entry to progress.txt: `## [timestamp] - Iteration $i KILLED (no result received) — auto-stashed and retrying`
- FR-5: On kill detection, decrement `$i` so the iteration is retried on the next loop pass
- FR-6: On kill detection, show a toast notification indicating the kill and retry
- FR-7: Replace CLAUDE.md Phase 1 step 4 with recovery logic: run `git status`, if dirty try `git stash pop`, if that fails `git stash drop` and continue
- FR-8: Add a "Build Strategy" section to CLAUDE.md with in-place-first, rsync fallback, no-cp-r, and TestContainers MCR note
- FR-9: Update README.md allowed hosts list to include `mcr.microsoft.com` / `*.mcr.microsoft.com`

## Non-Goals

- No changes to `Dockerfile.sandbox` (rsync is already installed)
- No changes to `settings.local.json` or Claude permissions
- No changes to the iteration streaming/parsing logic
- No automatic memory limit tuning for the sandbox container
- No retry limit for killed iterations (relies on existing `$MaxIterations` cap)

## Technical Considerations

- **Repo path inside sandbox:** The repo is mounted at the sandbox root. The exact path for `docker sandbox exec` commands needs to match the mount point used by `docker sandbox create`. Check the current `docker sandbox create` call for the mount layout.
- **Progress.txt path:** The orchestrator writes to `$ProgressFile` on the host. For kill logging, write directly to the host-side file (no need to exec into sandbox).
- **Iteration counter:** PowerShell `for` loop variable `$i` can be decremented with `$i--` inside the loop body. This causes the same iteration number to run again on the next pass.
- **Stash idempotency:** `git stash` is a no-op if the working tree is clean — safe to run unconditionally on kill detection.
- **Network policy:** The `docker sandbox network proxy` command already has multiple `--allow-host` flags; adding two more follows the existing pattern.

## Testing Strategy

This is infrastructure/tooling code (PowerShell + Markdown), not .NET application code. No BDD or integration tests apply.

- **Manual verification:** Parse `ralph-sandbox.ps1` for valid PowerShell syntax (`pwsh -c "Get-Content ralph-sandbox.ps1 | Out-Null"` or similar)
- **Read-through review:** Verify CLAUDE.md instructions are clear, consistent, and non-contradictory
- **Smoke test (optional):** Run a single Ralph iteration against an existing PRD to verify:
  - MCR images can be pulled (TestContainers tests pass)
  - Kill recovery doesn't interfere with normal completion flow
  - Network policy output shows MCR hosts

## Success Metrics

- Productive iteration ratio increases from ~55% to ~90%+
- Zero test failures caused by MCR network blocks
- Zero wasted iterations from dirty working trees after kills
- Killed iterations are automatically retried without operator intervention

## Open Questions

- Exact mount path inside the sandbox for `docker sandbox exec` git commands — needs verification from `docker sandbox create` output or inspection
- Should there be a max-retries-per-iteration guard to prevent infinite retry if an iteration always gets killed? (Current plan: no, `$MaxIterations` is the overall cap)
