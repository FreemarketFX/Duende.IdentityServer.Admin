# PRD: Post-Ralph Skill & Archive Restore

## Introduction

Three related improvements to the Ralph toolchain: (1) a new `post-ralph` skill that archives completed work and commits ralph artifacts, (2) automatic invocation of post-ralph from the sandbox on completion, and (3) archive-aware restore logic in the `prd` and `ralph` skills so previously archived work can be resumed.

## Goals

- Automate post-completion cleanup (archive + commit) via a dedicated skill
- Run post-ralph inside the sandbox as a final iteration after Ralph signals COMPLETE
- Allow `prd` and `ralph` skills to detect and restore archived work for the current branch

## User Stories

### US-001: Create post-ralph skill
**Description:** As a developer, I want a `/post-ralph` skill that archives the current `prd.json` and `progress.txt` to `tasks/archive/{jiraTicket}/`, removes them from `tasks/current/`, and commits all outstanding ralph-related files.

**Acceptance Criteria:**
- [ ] New skill at `skills/post-ralph/SKILL.md`
- [ ] Reads `tasks/current/prd.json` to extract `jiraTicket`
- [ ] Moves `prd.json` and `progress.txt` to `tasks/archive/{jiraTicket}/` (using unique-suffix if files already exist)
- [ ] Cleans up all remaining artifacts from `tasks/current/` (`.last-branch`, `ralph-sandbox.log`, `.iteration-output`, `nuget.config`)
- [ ] `tasks/current/` is empty after completion
- [ ] Stages and commits all ralph-related file changes (archive moves, cleanup)
- [ ] Commit message format: `chore(FMFX-XXXXX): archive completed ralph run`
- [ ] Gracefully handles missing files (no prd.json = nothing to archive)
- [ ] Build passes

### US-002: Run post-ralph as final sandbox iteration on completion
**Description:** As a developer, I want ralph-sandbox.ps1 to automatically run the post-ralph skill inside the sandbox after Ralph signals COMPLETE, so archiving and committing happens without manual intervention.

**Acceptance Criteria:**
- [ ] After detecting `<promise>COMPLETE</promise>`, run one more `docker sandbox run` with a prompt that triggers the post-ralph skill
- [ ] Remove the existing `Archive-CompletedRun` PowerShell function call (archiving now handled by the skill inside sandbox)
- [ ] Log that post-ralph is running
- [ ] Toast notification after post-ralph completes
- [ ] Script still exits 0 on success
- [ ] Build passes

### US-003: Add archive restore logic to ralph skill
**Description:** As a developer, I want the `/ralph` skill to check the archive for existing work matching the current branch before creating a new prd.json, and restore it to `tasks/current/` if found.

**Acceptance Criteria:**
- [ ] Before archiving or creating new prd.json, check `tasks/archive/` for a match
- [ ] Match by Jira ticket first: extract ticket from branch name, check if `tasks/archive/{ticket}/` exists
- [ ] Fall back to scanning `prd.json` files in archive subfolders for matching `branchName`
- [ ] If found, move (not copy) the archived `prd.json` and `progress.txt` back to `tasks/current/` (pick highest-suffix file if multiples exist, e.g., `prd-3.json` over `prd.json`)
- [ ] Inform the user that archived work was restored and show story status summary
- [ ] If no archive found, proceed with normal conversion flow
- [ ] Build passes

### US-004: Add archive restore logic to prd skill
**Description:** As a developer, I want the `/prd` skill to check the archive for an existing PRD matching the current branch and restore it before editing.

**Acceptance Criteria:**
- [ ] Before creating a new PRD, check `tasks/archive/` for a match
- [ ] Match by Jira ticket first: extract ticket from branch name, check if `tasks/archive/{ticket}/` exists
- [ ] Fall back to scanning `prd.json` files in archive subfolders for matching `branchName`
- [ ] If found, move (not copy) the archived `prd.json` and `progress.txt` back to `tasks/current/` (pick highest-suffix file if multiples exist)
- [ ] Inform the user that archived work was restored
- [ ] Proceed with normal PRD editing flow (user can update the restored PRD)
- [ ] Build passes

## Functional Requirements

- FR-1: `post-ralph` skill must read `jiraTicket` from `tasks/current/prd.json` for archive folder naming
- FR-2: Archive folder structure: `tasks/archive/{jiraTicket}/` with unique suffix (`prd-2.json`, `progress-2.txt`) for duplicates
- FR-3: Archive restore uses two-phase lookup: (a) extract Jira ticket from current branch name, match against archive folder names; (b) if no match, scan all `tasks/archive/*/prd.json` for matching `branchName` field
- FR-4: Restore is a move operation — archived files are removed from `tasks/archive/` when restored to `tasks/current/`
- FR-5: The post-ralph sandbox iteration uses `--permission-mode acceptEdits` like normal iterations
- FR-6: `ralph-sandbox.ps1` must remove the `Archive-CompletedRun` function and its call site, replacing with the sandbox-based post-ralph invocation

## Non-Goals

- No push or PR creation from post-ralph (archive + commit only)
- No changes to how Ralph agent itself operates inside the sandbox
- No changes to the progress.txt format or prd.json schema
- No UI or web interface

## Technical Considerations

- **Skill structure**: New `skills/post-ralph/SKILL.md` following the same pattern as existing skills
- **Sandbox prompt**: The post-ralph prompt should reference the skill by path (e.g., "Follow the instructions in claude-shared/skills/post-ralph/SKILL.md") since the sandbox Claude instance may not have skills registered
- **Archive lookup performance**: Ticket-based folder lookup (FR-3a) is O(1) directory check; branchName scan (FR-3b) requires reading prd.json from each archive subfolder — acceptable given small number of archives
- **Shared restore logic**: Both `prd` and `ralph` skills need the same archive restore logic. Document the algorithm clearly in each SKILL.md rather than trying to share code (skills are prompt-based, not executable)

## Success Metrics

- Zero manual archive/commit steps after Ralph completes
- Resuming work on an archived branch requires only running `/prd` or `/ralph` — no manual file moves

## Resolved Questions

- **Post-ralph cleanup scope:** Yes, clean everything from `tasks/current/` — remove `.last-branch`, `ralph-sandbox.log`, `.iteration-output`, `nuget.config`. Leave `tasks/current/` empty after archiving.
- **Multiple archive files:** Restore the highest-suffix file (e.g., `prd-3.json` over `prd.json`), as it represents the most recent run.
