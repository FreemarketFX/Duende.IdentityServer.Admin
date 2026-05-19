---
name: post-ralph
description: "Archives a completed Ralph run and commits resulting artifacts. Activated by: ralph archival, ralph cleanup, post-ralph finalization."
license: MIT
---

# Post-Ralph: Archive & Commit

Archives a completed Ralph run and commits all artifacts. Run this after Ralph signals `<promise>COMPLETE</promise>` or when you want to manually archive the current run.

---

## The Job

1. **Find** `prd.json` — check `tasks/current/` then `apps/*/tasks/current/`
2. **Archive** `prd.json` and `progress.txt` to the sibling `archive/{identifier}/` directory
3. **Clean up** all remaining artifacts from the PRD directory
4. **Commit** all changes

If `prd.json` cannot be found in any location, there is nothing to archive — inform the user and stop.

---

## Step-by-Step

### 0. Load Project Rules

Before archiving, load project rules to verify PRD completeness:

1. **Find CLAUDE.md**: Run `Glob("CLAUDE.md")` from the repo root. If not found, try `Glob("**/CLAUDE.md")` and take the first match not inside `claude-shared/`, `node_modules/`, or `.claude/`.
2. **Check MEMORY.md**: Run `Glob("MEMORY.md")` from the repo root. If found, read any `feedback` type entries.
3. **PRD verification**: After reading `prd.json` (next step), verify every completed story has `"passes": true`. If any completed story has `"passes": false` but the code is committed, update it before archiving.

If no repo-level CLAUDE.md is found, skip rules loading.

### 1. Find and Read the PRD

Search these locations in order (all relative to repo root):

1. `tasks/current/prd.json`
2. `apps/*/tasks/current/prd.json`

Use whichever path exists. Remember this directory as `$PRD_DIR` for later steps.

Extract `jiraTicket` for the archive folder name. If `jiraTicket` is empty, use `branchName` instead.

### 2. Create Archive Folder

```bash
mkdir -p $PRD_DIR/../archive/{identifier}/
```

Where `{identifier}` is the Jira ticket (e.g. `FMFX-12345`) or branch name. The archive lives as a sibling of the `current/` directory.

### 3. Handle Duplicate Archives

If files already exist in the archive folder (from a previous run of the same ticket):

- Find the highest existing suffix: `prd.json`, `prd-2.json`, `prd-3.json`, etc.
- Use the next suffix number for the new files

```
tasks/archive/FMFX-12345/
├── prd.json          # first run
├── progress.txt      # first run
├── prd-2.json        # second run
└── progress-2.txt    # second run
```

If no duplicates exist, use the base names (`prd.json`, `progress.txt`).

### 4. Move Files to Archive

Move (not copy) these files from `$PRD_DIR/` to the archive folder:

- `prd.json` → `$PRD_DIR/../archive/{identifier}/prd.json` (or `prd-N.json`)
- `progress.txt` → `$PRD_DIR/../archive/{identifier}/progress.txt` (or `progress-N.txt`)

Skip any file that doesn't exist.

### 5. Clean Up $PRD_DIR/

Delete all remaining files from `$PRD_DIR/`. Common artifacts to remove:

- `.last-branch`
- `ralph-sandbox.log`
- `.iteration-output`
- `nuget.config`
- Any other files

After cleanup, `$PRD_DIR/` must be empty. Verify with `ls $PRD_DIR/`.

### 6. Commit

**IMPORTANT: You MUST use `git add -A`.** Do NOT use `git add <specific-files>` — the move operation creates both deletions (in `tasks/current/`) and additions (in `tasks/archive/`). Only `git add -A` stages both sides atomically. Using specific file paths will fail because the deleted files no longer exist on disk.

Run this exact sequence from the **repository root**:

```bash
git add -A
git status          # verify only archive moves + cleanup, nothing unexpected
git diff --cached --stat
git commit -m "chore(FMFX-XXXXX): archive completed ralph run"
```

If no Jira ticket:

```
chore: archive completed ralph run [{branchName}]
```

### 7. Suggest log analysis

After the commit succeeds, print this to the user (do NOT auto-run it — pattern catalogue may have new entries since the last analysis, and the user may want to skip):

```
Run the postmortem before context fades:

  /ralph-log-doctor $PRD_DIR/../archive/{identifier}/ralph-sandbox.log

This mines the run log for recurring failures and emits a punch list of fixes routed to claude-shared/ vs this repo. Add --metrics for run-level waste stats.
```

Substitute the actual archive path. Stop after printing — the user decides whether to invoke.

---

## Edge Cases

- **No prd.json in any location**: Nothing to archive. Inform user and stop.
- **No progress.txt**: Archive prd.json only. Not an error.
- **Empty jiraTicket and branchName**: Use `unknown` as the archive folder name.
- **$PRD_DIR/ already empty after moving prd/progress**: Cleanup step is a no-op. That's fine.

---

## Checklist

- [ ] Found `prd.json` and identified `$PRD_DIR`
- [ ] Extracted identifier (jiraTicket or branchName)
- [ ] Created archive folder at `$PRD_DIR/../archive/{identifier}/`
- [ ] Handled duplicate archives (suffix numbering if needed)
- [ ] Moved `prd.json` to archive
- [ ] Moved `progress.txt` to archive (if it existed)
- [ ] Cleaned up all remaining files from `$PRD_DIR/`
- [ ] `$PRD_DIR/` is empty
- [ ] Committed all changes with correct message format
