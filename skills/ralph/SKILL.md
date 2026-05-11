---
name: ralph
description: "Convert PRDs to prd.json format for the Ralph autonomous agent system. Use when you have an existing PRD and need to convert it to Ralph's JSON format. Triggers on: convert this prd, turn this into ralph format, create prd.json from this, ralph json."
license: MIT
---

# Ralph PRD Converter

Converts existing PRDs to the prd.json format that Ralph uses for autonomous execution.

---

## The Job

1. **Check archive for existing work** matching the current branch (see [Archive Restore](#archive-restore) section below)
   - **If a match is found: restore the files, show a story status summary, and STOP. Do not proceed to step 2 or beyond. The skill exits here.**
2. **Archive** any existing `prd.json` and `progress.txt` (see [Archiving](#archiving-previous-runs) section below)
3. Take a PRD (markdown file or text) and convert it to `prd.json` in `./tasks/current/`
4. Reset `progress.txt` with a fresh header
5. **Commit** all changes (archive + new files) before completing

**Branch handling:**
1. Run `git branch --show-current` to check current branch
2. If NOT on `main`: use current branch name for `branchName`, extract Jira ticket (FMFX-XXXXX) from branch name for `jiraTicket`
3. If on `main`: ask user for Jira ticket, derive branch name as `FMFX-XXXXX-[feature-name-kebab-case]`, then **create and checkout the new branch** before writing prd.json

---

## Output Format

```json
{
  "project": "[Project Name]",
  "jiraTicket": "FMFX-XXXXX",
  "branchName": "FMFX-XXXXX-[feature-name-kebab-case]",
  "description": "[Feature description from PRD title/intro]",
  "userStories": [
    {
      "id": "US-001",
      "title": "[Story title]",
      "description": "As a [user], I want [feature] so that [benefit]",
      "acceptanceCriteria": [
        "Criterion 1",
        "Criterion 2",
        "Typecheck passes"
      ],
      "priority": 1,
      "passes": false,
      "notes": ""
    }
  ]
}
```

---

## Story Size: The Number One Rule

**Each story must be completable in ONE Ralph iteration (one context window).**

Ralph spawns a fresh Amp instance per iteration with no memory of previous work. If a story is too big, the LLM runs out of context before finishing and produces broken code.

### Right-sized stories:
- Add a database column and migration
- Add a UI component to an existing page
- Update a server action with new logic
- Add a filter dropdown to a list

### Too big (split these):
- "Build the entire dashboard" - Split into: schema, queries, UI components, filters
- "Add authentication" - Split into: schema, middleware, login UI, session handling
- "Refactor the API" - Split into one story per endpoint or pattern

**Rule of thumb:** If you cannot describe the change in 2-3 sentences, it is too big.

---

## Story Ordering: Dependencies First

Stories execute in priority order. Earlier stories must not depend on later ones.

**Correct order:**
1. Schema/database changes (migrations)
2. Server actions / backend logic
3. UI components that use the backend
4. Dashboard/summary views that aggregate data

**Wrong order:**
1. UI component (depends on schema that does not exist yet)
2. Schema change

---

## Acceptance Criteria: Must Be Verifiable

Each criterion must be something Ralph can CHECK, not something vague.

### Good criteria (verifiable):
- "Add `status` column to tasks table with default 'pending'"
- "Filter dropdown has options: All, Active, Completed"
- "Clicking delete shows confirmation dialog"
- "Typecheck passes"
- "Tests pass"

### Bad criteria (vague):
- "Works correctly"
- "User can do X easily"
- "Good UX"
- "Handles edge cases"

### Always include as final criterion:
```
"Typecheck passes"
```

For stories with testable logic, also include:
```
"Tests pass"
```

### For stories that change UI, also include:
```
"Verify in browser using dev-browser skill"
```

Frontend stories are NOT complete until visually verified. Ralph will use the dev-browser skill to navigate to the page, interact with the UI, and confirm changes work.

---

## Conversion Rules

1. **Each user story becomes one JSON entry**
2. **IDs**: Sequential (US-001, US-002, etc.)
3. **Priority**: Based on dependency order, then document order
4. **All stories**: `passes: false` and empty `notes`
5. **jiraTicket**: Extract from current branch if not on `main`, otherwise ask user
6. **branchName**: If not on `main`, use current branch name. If on `main`, format as `FMFX-XXXXX-[feature-name-kebab-case]`
7. **Always add**: "Typecheck passes" to every story's acceptance criteria

---

## Splitting Large PRDs

If a PRD has big features, split them:

**Original:**
> "Add user notification system"

**Split into:**
1. US-001: Add notifications table to database
2. US-002: Create notification service for sending notifications
3. US-003: Add notification bell icon to header
4. US-004: Create notification dropdown panel
5. US-005: Add mark-as-read functionality
6. US-006: Add notification preferences page

Each is one focused change that can be completed and verified independently.

---

## Example

**Input PRD:**
```markdown
# Task Status Feature

Add ability to mark tasks with different statuses.

## Requirements
- Toggle between pending/in-progress/done on task list
- Filter list by status
- Show status badge on each task
- Persist status in database
```

**Output prd.json:**
```json
{
  "project": "TaskApp",
  "jiraTicket": "FMFX-12345",
  "branchName": "FMFX-12345-task-status",
  "description": "Task Status Feature - Track task progress with status indicators",
  "userStories": [
    {
      "id": "US-001",
      "title": "Add status field to tasks table",
      "description": "As a developer, I need to store task status in the database.",
      "acceptanceCriteria": [
        "Add status column: 'pending' | 'in_progress' | 'done' (default 'pending')",
        "Generate and run migration successfully",
        "Typecheck passes"
      ],
      "priority": 1,
      "passes": false,
      "notes": ""
    },
    {
      "id": "US-002",
      "title": "Display status badge on task cards",
      "description": "As a user, I want to see task status at a glance.",
      "acceptanceCriteria": [
        "Each task card shows colored status badge",
        "Badge colors: gray=pending, blue=in_progress, green=done",
        "Typecheck passes",
        "Verify in browser using dev-browser skill"
      ],
      "priority": 2,
      "passes": false,
      "notes": ""
    },
    {
      "id": "US-003",
      "title": "Add status toggle to task list rows",
      "description": "As a user, I want to change task status directly from the list.",
      "acceptanceCriteria": [
        "Each row has status dropdown or toggle",
        "Changing status saves immediately",
        "UI updates without page refresh",
        "Typecheck passes",
        "Verify in browser using dev-browser skill"
      ],
      "priority": 3,
      "passes": false,
      "notes": ""
    },
    {
      "id": "US-004",
      "title": "Filter tasks by status",
      "description": "As a user, I want to filter the list to see only certain statuses.",
      "acceptanceCriteria": [
        "Filter dropdown: All | Pending | In Progress | Done",
        "Filter persists in URL params",
        "Typecheck passes",
        "Verify in browser using dev-browser skill"
      ],
      "priority": 4,
      "passes": false,
      "notes": ""
    }
  ]
}
```

---

## Archive Restore

**Before archiving or creating a new prd.json, check the archive for existing work that matches the current branch.**

This lets developers resume a previous Ralph run after it was archived (e.g., by the post-ralph skill).

### Restore Procedure

1. Extract the Jira ticket from the current branch name (pattern: `FMFX-XXXXX_description` or `FMFX-XXXXX-description`)
2. **Match by ticket:** Check if `tasks/archive/{ticket}/` exists (e.g., `tasks/archive/FMFX-12345/`)
3. **Fall back to branchName scan:** If no ticket match, scan all `tasks/archive/*/prd.json` files and check if any has a `branchName` field matching the current branch
4. If a match is found:
   - Move (not copy) `prd.json` from the archive folder back to `tasks/current/prd.json`
     - If multiple `prd.json` files exist (e.g., `prd.json`, `prd-1.json`, `prd-2.json`), pick the one with the **highest suffix number** (or the base `prd.json` if no suffixed versions exist)
   - Move `progress.txt` back to `tasks/current/progress.txt` (same suffix logic)
   - Remove the archive subfolder if it is now empty
   - Print a message: "Restored archived work from `tasks/archive/{folder}/`"
   - Show a story status summary table:
     ```
     Story    | Title                        | Status
     ---------|------------------------------|--------
     US-001   | Add status field             | DONE
     US-002   | Display status badge         | PENDING
     US-003   | Add status toggle            | PENDING
     ```
   - **Stop here.** Do not proceed with PRD conversion. The user can now run Ralph to continue.
5. If no match is found, proceed with the normal flow (archive existing → convert → commit)

---

## Archiving Previous Runs

**Always archive before writing a new prd.json.** This is mandatory, not optional.

1. Check if `tasks/current/prd.json` exists
2. If it exists:
   - Read it and extract the Jira ticket (e.g. `FMFX-12345`) from `jiraTicket`
   - Create archive folder: `tasks/archive/FMFX-12345/`
   - Move `prd.json` to the archive folder
   - Move `progress.txt` to the archive folder (if it exists)
3. If it does not exist, skip archiving

---

## Final Step: Commit All Changes

After writing prd.json and progress.txt, commit everything in a single commit:

- `tasks/archive/FMFX-XXXXX/*` - archived previous run (if any)
- `tasks/prd-[feature-name].md` - the PRD markdown
- `tasks/current/prd.json` - the new Ralph JSON
- `tasks/current/progress.txt` - fresh progress file

Use commit message: `docs: Add PRD for [feature-name]`

---

## Checklist

- [ ] **Previous run archived** (if prd.json exists, archive it first)
- [ ] Each story is completable in one iteration (small enough)
- [ ] Stories are ordered by dependency (schema to backend to UI)
- [ ] Every story has "Typecheck passes" as criterion
- [ ] UI stories have "Verify in browser using dev-browser skill" as criterion
- [ ] Acceptance criteria are verifiable (not vague)
- [ ] No story depends on a later story
- [ ] **Committed** archive, PRD markdown, prd.json, and progress.txt
