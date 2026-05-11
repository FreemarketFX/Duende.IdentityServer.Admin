---
name: jira-csv
description: "Generate Jira stories from source material (PRDs, specs, docs, pasted text, URLs) and output a Jira Cloud CSV import file. Use to create Jira tickets, break work into stories, export to CSV, or prepare a Jira import — even if user says 'create a ticket' or 'generate stories from this'. Triggers on: jira csv, create jira stories, create jira ticket, export to jira, jira import, break into stories, generate tickets, generate stories from, stories from prd, csv for jira."
allowed-tools: Glob, Grep, Read, Write, AskUserQuestion, WebFetch
license: MIT
---

# Jira CSV Exporter

Analyze source material, break it into Jira stories, and output a Jira Cloud-compatible CSV import file.

---

## The Job

1. Receive source material (file path, URL, pasted text, or PRD from this repo)
2. Analyze the source and extract discrete pieces of work
3. Ask the user for Jira project metadata and field defaults
4. Generate user stories with proper formatting
5. Preview stories for user approval
6. Write a valid Jira Cloud CSV import file

**Important:** Do NOT import to Jira. Just create the CSV file. The user imports it themselves.

---

## Step 1: Receive Source Material

Examine what the user provided and determine the source type:

| Input | Detection | Action |
|-------|-----------|--------|
| File path (e.g., `tasks/prd-foo.md`, `./spec.md`) | Contains `/` or `\`, or ends in `.md`/`.txt`/`.doc` | Read the file |
| URL (e.g., `https://...`) | Starts with `http://` or `https://` | Fetch with WebFetch |
| PRD name (e.g., "the auth PRD") | No file or URL pattern match | Search `tasks/prd-*.md` with Glob, present matches, let user pick |
| Pasted text | Multiple lines of content in the message | Use directly |
| Nothing | No source material in the prompt | Ask the user for it |

### If searching for a PRD

Use `Glob("tasks/prd-*.md")` to list available PRDs. If multiple exist, present them as numbered options via AskUserQuestion.

### Confirm understanding

After receiving source material, confirm before proceeding:

```
I've read [source]. Here's what I understand:

**Topic:** [feature/project name]
**Scope:** [1-2 sentence summary]
**Estimated stories:** [rough count — may change after full analysis]

Does this look right, or should I focus on a specific section?
```

---

## Step 2: Analyze Source Material

Extract discrete units of work. Look for:

- **User stories** already defined — use them directly
- **Requirements** (functional, non-functional) — each becomes a story
- **Features or capabilities** in prose — break into implementable stories
- **Technical tasks** (migrations, infrastructure, config) — separate from feature stories
- **Acceptance criteria** — attach to their parent stories

### Story sizing

Each story should be:
- Completable by one person in 1-3 days
- Independently deliverable
- Testable — someone can verify it works

Split stories that are too large. Merge tightly coupled tiny requirements.

### Story ordering

Order by dependency, then logical flow:
1. Schema/data model changes
2. Backend/API implementation
3. Frontend/UI implementation
4. Integration and cross-cutting concerns
5. Documentation and cleanup

If dependency order cannot be determined from the source, preserve the order from the source material.

---

## Step 3: Gather Jira Metadata

Ask the user for project-specific Jira configuration. Present these as conversational questions in your response — use AskUserQuestion for structured choices (max 4 options per call) and free-text follow-ups for values like project key and epic name.

### Question batch 1 — Core fields

Ask these together in one message. The user can respond naturally (e.g., "FMFX, yes call it Spring 2026, medium priority"):

```
I need some Jira details before generating the CSV:

1. **Project key** — The Jira project prefix (e.g., PROJ, FMFX)?

2. **Epic** — Should these stories belong to an Epic? If yes, what's the Epic name?

3. **Default Priority** — What priority for most stories?
   A. High
   B. Medium (recommended)
   C. Low
```

### Question batch 2 — Optional fields

```
4. **Components** — Add component tags? (comma-separated, or skip)

5. **Labels** — Add labels? (comma-separated, or skip)

6. **Story structure** — How should I organize the stories?
   A. Flat stories only (recommended for most imports)
   B. Stories with subtasks (group related tasks under parent stories)
```

### Question batch 3 — Extra fields

Ask this only if the user's source material mentions assignees, versions, or sprints — or if the user explicitly asks about additional fields:

```
Any additional Jira fields to include?
A. Assignee (email address)
B. Fix Version
C. Sprint name
D. No additional fields — let's generate
```

---

## Step 4: Generate Stories

For each unit of work from Step 2, generate a story:

### Field rules

| Field | Rule |
|-------|------|
| **Summary** | Short, imperative title. Under 80 chars. Start with a verb. |
| **Issue Type** | `Story` for feature work, `Task` for technical work. Default: `Story`. |
| **Priority** | Use the default from Step 3 unless a story clearly warrants different priority. |
| **Description** | "As a [user], I want [feature] so that [benefit]" for Stories. Include acceptance criteria. |
| **Epic Link** | The Epic name from Step 3 (if provided). |
| **Components** | From Step 3 defaults. Individual stories may override if the source material warrants it. |
| **Labels** | From Step 3 defaults. Individual stories may override. |

### Description format

Use **Jira wiki markup** inside descriptions — not markdown. The Jira CSV importer interprets description fields as wiki markup, so markdown headings and bullets will render incorrectly.

```
As a [user role], I want [capability] so that [benefit].

h3. Acceptance Criteria
* [Specific, verifiable criterion]
* [Another criterion]

h3. Notes
[Any implementation hints, constraints, or context from the source material]
```

Key Jira wiki markup rules:
- `h3.` for headings (not `###`)
- `*` for bullet lists (not `-`)
- `{code}...{code}` for code blocks (not triple backticks)
- `_italic_` and `*bold*` for emphasis

### Epic row

When the user provided an Epic name, generate it as the **first row** in the CSV:
- Issue Type = `Epic`
- Summary = the Epic name
- `Epic Name` column = the Epic name (this is what Jira uses to create the Epic)
- `Epic Link` column = blank for the Epic row
- All subsequent story rows: `Epic Name` = blank, `Epic Link` = the Epic name string

### Subtask generation (only if user chose subtasks in batch 2)

When generating subtasks:
- Assign sequential `Issue id` to every row (including the Epic row), starting at 1
- Parent stories: Issue Type = `Story`, `Parent id` left empty
- Subtasks: Issue Type = `Sub-task`, `Parent id` = their parent story's `Issue id`
- Epic row: `Parent id` left empty

Omit `Issue id` and `Parent id` columns entirely when subtasks are not enabled.

---

## Step 5: Preview and Refine

Present all stories in a summary table:

```
## Story Preview — [N] stories for [Project Key]

| # | Type | Summary | Priority |
|---|------|---------|----------|
| 1 | Epic | Spring 2026 Release | - |
| 2 | Story | Create user preferences database schema | Medium |
| 3 | Story | Add preference update API endpoint | Medium |
| 4 | Story | Build preferences settings page | Medium |
| 5 | Task | Write API integration tests | Medium |

**Epic:** Spring 2026 Release
**Components:** Backend, Frontend
**Labels:** mvp, preferences
```

Then ask:

```
Review the stories above. What would you like to do?
A. Looks good — generate the CSV
B. Edit specific stories (tell me which numbers and what to change)
C. Add more stories
D. Remove some stories (tell me which numbers)
```

If the user chooses B, C, or D, apply changes and re-display. Repeat until they choose A.

---

## Step 6: Write the CSV

### Ask for output path

```
Where should I save the CSV?
A. tasks/jira-import-{feature-name}.csv (recommended)
B. Current directory: ./jira-import-{feature-name}.csv
C. Custom path — I'll specify
```

If the user picks C, ask them for the full path as free text.

### CSV construction rules (Jira Cloud import spec)

These rules are critical — an incorrectly formatted CSV will fail on import or create garbled stories.

**1. Header row required** — first row is column names.

**2. Multi-value fields use duplicate column headers.** If any story has 2 Components, the header needs `Components,Components`. Calculate the max count for each multi-value field across all stories and emit that many columns.

**3. Double-quote all fields** to be safe — any field could contain commas (e.g., a Summary like "Login, Register, and Logout flows"). At minimum, always double-quote Description.

**4. Escape internal quotes** — use two consecutive double quotes inside a quoted field: `"She said ""hello"""`

**5. Omit empty columns entirely.** If no stories have Components, don't include the Components column at all. Only include columns that carry data.

**6. Epic Name vs Epic Link:**
- The Epic row populates `Epic Name` and leaves `Epic Link` blank
- Story rows leave `Epic Name` blank and populate `Epic Link` with the Epic name string
- Both columns must be present in the header when an Epic is included
- Note: in next-gen/team-managed Jira projects, `Epic Link` may not exist — stories link to epics via `Parent` instead. Flag this to the user if they mention a team-managed project.

**7. Subtask columns** (only when subtasks enabled):
- `Issue id` — sequential numeric ID for every row
- `Parent id` — references the parent's Issue id. Empty for top-level stories.

**8. Encoding** — UTF-8, no BOM.

### Column order

Use this column order (omitting any columns with no data):

```
Issue id,Parent id,Summary,Issue Type,Priority,Description,Epic Name,Epic Link,Components,...,Labels,...,Assignee,Fix Version,Sprint
```

### Example CSV — flat stories with Epic

This example shows 2 Components columns (max 2 across all stories) and 2 Labels columns (max 2 across all stories). Stories with fewer values leave extra columns empty.

```csv
Summary,Issue Type,Priority,Description,Epic Name,Epic Link,Components,Components,Labels,Labels
"Spring 2026 Release","Epic","Medium","Epic for spring 2026 release work","Spring 2026 Release","","Backend","","mvp",""
"Create user preferences schema","Story","Medium","As a developer, I want a database schema for user preferences so that preferences persist across sessions.

h3. Acceptance Criteria
* Preferences table with columns: user_id, preference_key, preference_value, updated_at
* Migration runs successfully
* Indexes on user_id and preference_key","","Spring 2026 Release","Backend","Database","mvp","backend"
"Add preference update API endpoint","Story","Medium","As a user, I want to update my preferences via API so that my settings are saved.

h3. Acceptance Criteria
* PUT /api/users/{id}/preferences endpoint exists
* Validates preference keys against allowed list
* Returns 200 with updated preference
* Returns 422 for invalid key","","Spring 2026 Release","Backend","","mvp",""
```

### Example CSV — stories with subtasks

```csv
Issue id,Parent id,Summary,Issue Type,Priority,Description,Epic Name,Epic Link,Components,Labels
1,,"Spring 2026 Release","Epic","Medium","Epic for spring release","Spring 2026 Release","","Backend","mvp"
2,,"Create user preferences feature","Story","Medium","Parent story for preferences work","","Spring 2026 Release","Backend","mvp"
3,2,"Create preferences database table","Sub-task","Medium","Create the schema and run migration","","","Database","backend"
4,2,"Add preferences API endpoint","Sub-task","Medium","Implement the REST endpoint","","","Backend","backend"
5,,"Build preferences UI","Story","Medium","Parent story for preferences UI","","Spring 2026 Release","Frontend","mvp"
6,5,"Add preferences page layout","Sub-task","Medium","Create the settings page structure","","","Frontend","ui"
```

### After writing

Display a summary:

```
CSV written to `{path}`

**Stories:** [N] (+ 1 Epic)
**Columns:** [list headers]

To import into Jira:
1. Go to your Jira project > Project Settings > Import Issues (or use the global CSV importer)
2. Upload the CSV file
3. Map the columns — they should auto-map by name
4. Review the preview and confirm import

Note: If the Epic doesn't exist yet in Jira, import the Epic row first (Jira may handle this automatically, but verify in the import preview).
```

---

## Edge Cases

### Source material has no clear stories

```
The source material is too high-level for individual stories. I can:
A. Generate broad stories and mark them for refinement in Jira
B. Ask you clarifying questions to get more detail
C. Create one story per major section/feature area
```

### Source is already a PRD with user stories

If the PRD already has well-defined user stories (e.g., from the `/prd` skill), map them directly:
- PRD story title -> Summary
- PRD description -> Description
- PRD acceptance criteria -> Description checklist (convert `- [ ] criterion` to `* criterion` — Jira wiki markup has no checkbox syntax)

### Very large source (20+ stories)

Batch the preview into groups of 10. Ask for approval per batch to avoid overwhelming the user.

### No Epic provided

Omit both `Epic Name` and `Epic Link` columns entirely. No empty Epic columns.

---

## Checklist (internal — do not show to user)

- [ ] Source material received and understood
- [ ] Confirmed understanding with user before proceeding
- [ ] Jira metadata collected (project key, epic, priority, components, labels)
- [ ] Stories follow "As a... I want... so that..." format (for Story type)
- [ ] Descriptions use Jira wiki markup, not markdown
- [ ] Each story is independently deliverable and sized for 1-3 days
- [ ] Stories ordered by dependency
- [ ] Epic row included as first data row (if Epic name provided)
- [ ] Preview shown and user approved before writing CSV
- [ ] Asked user for output path
- [ ] CSV has correct header with duplicated multi-value columns
- [ ] Description fields are double-quoted with escaped internal quotes
- [ ] Multi-value columns have consistent count across all rows
- [ ] Empty columns omitted entirely
- [ ] Import instructions shown to user
