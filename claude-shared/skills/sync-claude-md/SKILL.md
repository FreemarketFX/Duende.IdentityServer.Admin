---
name: sync-claude-md
description: "Compares repo CLAUDE.md with the shared template, shows differences, then commits and opens a PR. Activated by: claude sync, template alignment."
license: MIT
---

# Sync CLAUDE.md

Compare current repo's CLAUDE.md against the shared template and selectively add missing content.

---

## The Job

1. Read both files and parse into sections
2. Identify missing content in the current CLAUDE.md
3. Present missing items as selectable options
4. Apply selected changes
5. Create branch (if on main), commit, and raise PR

---

## Step 1: Read and Parse Files

Read both markdown files:

```bash
# Template (relative path from current repo)
cat ../claude-shared/CLAUDE_TEMPLATE.md

# Current repo
cat CLAUDE.md
```

Parse each file into sections by `##` headers. Within each section, identify:
- Bullet point rules (lines starting with `- `)
- Code blocks
- Table rows
- Subsections (`###`)

---

## Step 2: Compare and Identify Differences

For each section in CLAUDE_TEMPLATE.md:

1. Check if section exists in CLAUDE.md
2. If section exists, compare content line-by-line
3. Track missing items:
   - Entire missing sections
   - Missing bullet points within existing sections
   - Missing table rows
   - Missing subsections

**Important:** Focus on the "NEVER Do" section and other rule-based sections. Skip sections that are clearly template placeholders.

---

## Step 3: Present Selectable List

Use AskUserQuestion with multiSelect=true to let user choose what to add.

Group by section:

```
Which items would you like to add to CLAUDE.md?

## NEVER Do (3 missing items)
- [ ] Use test doubles for our own code - if you can `new` it, test the real thing
- [ ] Use StubRepositories for SQL - use real SQL via TestContainers
- [ ] Stub `IRepository` - use real Cosmos via TestContainers

## Code Style (1 missing item)
- [ ] Target-typed `new()`: `MyClass x = new();` not `var x = new MyClass();`
```

**Limit:** AskUserQuestion supports max 4 options per question. If more items exist, batch into multiple questions or group by section.

---

## Step 4: Apply Selected Changes

For each selected item:

1. Find the appropriate section in CLAUDE.md
2. If section doesn't exist, create it
3. Add the item in the correct location (maintain ordering from template)
4. Use the Edit tool to make changes

**Preserve existing content** - only add, never remove or modify existing rules.

---

## Step 5: Branch, Commit, and PR

### Check current branch

```bash
git branch --show-current
```

### If on main branch

Ask the user for a Jira ticket number (e.g., `FMFX-12345`). If they don't have one, use `chore` instead of `docs({TICKET})` in the commit/PR titles below. Substitute `{TICKET}` in all commands below with that ticket.

Create a new branch:

```bash
git checkout -b {TICKET}_sync-claude-md
```

### Stage and commit

```bash
git add CLAUDE.md
git commit -m "$(cat <<'EOF'
docs({TICKET}): sync CLAUDE.md with shared template

- Added missing rules from CLAUDE_TEMPLATE.md
EOF
)"
```

### Push and create PR

```bash
git push -u origin HEAD
gh pr create --title "docs({TICKET}): sync CLAUDE.md with shared template" --body "$(cat <<'EOF'
## Summary

Synced CLAUDE.md with the latest shared template rules.

### Added Items

[List the items that were added]

## Test plan

- [ ] Review added rules match template
- [ ] Verify no existing content was modified

---
Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## Output Format

After completion, display:

```markdown
## Sync Complete

**Branch:** {TICKET}_sync-claude-md
**PR:** [PR URL]

### Items Added

- [List of added items]

### Skipped Items

- [List of items user chose not to add, if any]
```

---

## Edge Cases

### No CLAUDE.md exists

If the current repo has no CLAUDE.md:
1. Copy CLAUDE_TEMPLATE.md as starting point
2. Ask user which sections to keep
3. Commit and PR as normal

### Template not found

If ../claude-shared/CLAUDE_TEMPLATE.md doesn't exist:
1. Output error: "Template not found at ../claude-shared/CLAUDE_TEMPLATE.md"
2. Ask user for alternate path

### No differences found

If CLAUDE.md already matches template:
1. Output: "CLAUDE.md is already in sync with template"
2. Exit without changes

### Already on feature branch

If not on main:
1. Skip branch creation
2. Commit to current branch
3. Create PR from current branch to main
