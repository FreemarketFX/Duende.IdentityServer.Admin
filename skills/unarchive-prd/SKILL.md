---
name: unarchive-prd
description: "Move an archived prd.json and progress.txt back to tasks/current/ for another Ralph run. Use whenever a user wants to unarchive, restore, resume, or re-run a previously archived PRD. Triggers on: unarchive prd, restore prd, resume ralph, bring back prd, move prd back to current."
license: MIT
---

# Unarchive PRD

Restores an archived `prd.json` and `progress.txt` from `tasks/archive/{ticket}/` back into `tasks/current/` so Ralph can be run again.

---

## Step 1: Resolve the Ticket Number

Try these sources in order:

1. **Argument** — if the user passed a ticket number (e.g., `/unarchive-prd FMFX-12345`), use it
2. **Branch name** — run `git branch --show-current` and extract the Jira ticket (pattern: `FMFX-XXXXX`)
3. **Ask** — if neither yields a ticket, list the folders in `tasks/archive/` and ask the user which one to restore

---

## Step 2: Locate the Archive

Check if `tasks/archive/{ticket}/` exists. If not, fall back to scanning all `tasks/archive/*/prd.json` files for a matching `jiraTicket` field.

If no match is found, tell the user and stop.

### Suffix handling

The archive may contain suffixed duplicates from multiple runs (e.g., `prd.json`, `prd-2.json`, `prd-3.json`). Always pick the **highest suffix** — that's the most recent run. Same logic applies to `progress.txt` / `progress-N.txt`.

---

## Step 3: Check for Existing Files in `tasks/current/`

Before moving anything, check if `tasks/current/` already contains a `prd.json` or `progress.txt`.

If it does:

1. Read both the existing current file(s) and the archived file(s)
2. Summarise the key differences to the user — ticket number, story count, which stories have `passes: true`, any content divergence
3. Ask the user how to proceed:
   - **Replace** — overwrite current with archived
   - **Cancel** — leave everything as-is

Do not move files until the user confirms.

---

## Step 4: Move Files

Move (not copy) from the archive folder to `tasks/current/`:

- `prd.json` (or highest-suffixed variant) → `tasks/current/prd.json`
- `progress.txt` (or highest-suffixed variant) → `tasks/current/progress.txt`

Skip `progress.txt` if it doesn't exist in the archive — not an error.

If the archive folder is empty after the move, delete it.

---

## Step 5: Show Summary

Print a story status table so the user knows where things stand:

```
Story    | Title                        | Status
---------|------------------------------|--------
US-001   | Add status field             | DONE
US-002   | Display status badge         | PENDING
```

Status is `DONE` if `passes: true`, otherwise `PENDING`.

---

## Edge Cases

- **No archive folder found**: inform user, list available archives, stop
- **No prd.json in archive**: inform user, stop — nothing useful to restore
- **No progress.txt in archive**: move prd.json only, not an error
- **Archive folder has other files besides prd/progress**: leave them in place, only move the prd.json and progress.txt
