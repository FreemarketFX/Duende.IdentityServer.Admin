---
name: ralph-log-doctor
description: "Postmortem analysis of a ralph-sandbox.log run. Locates the log, spawns the ralph-log-doctor subagent to mine recurring failure patterns, writes the report alongside the run, and gates fixes on user approval. Triggers on: ralph log doctor, analyse ralph log, ralph log analysis, ralph postmortem, ralph failures, why did ralph fail, ralph sandbox log, post-ralph review, ralph diagnosis."
license: MIT
---

# Ralph Log Doctor

Thin wrapper around the `ralph-log-doctor` agent. Locates the log, parses optional flags, spawns the agent with a restricted toolset, writes the report next to the run, and gates any follow-up actions.

The heavy lifting (parsing, pattern matching, redaction, report generation) lives in the agent definition at `.claude/agents/ralph-log-doctor.md`. Keep this skill file thin.

---

## Flags

The user may pass any of:

- `--metrics` — include the run-level metrics section (default off)
- `--shared-only` — punch list contains only `claude-shared/` fixes
- `--repo-only` — punch list contains only repo-specific fixes
- `--no-write` — skip writing the report file (default writes alongside the log)
- A log path — explicit `tasks/archive/<run>/ralph-sandbox.log`

If conflicting scope flags are passed (`--shared-only` + `--repo-only`), error and ask the user to pick one.

---

## Step 1: Locate the Log

If a path is provided as argument, use it. Otherwise auto-detect:

```bash
find tasks -name ralph-sandbox.log -type f 2>/dev/null | xargs ls -t 2>/dev/null | head -1
```

If multiple recent runs exist and no flag was given, ask the user (default: most recent).
If no log found, ask the user for the path.

Capture the **literal absolute path** for use throughout — shell vars don't persist between Bash calls.

---

## Step 2: Sanity Check

```bash
test -s "$LOG_PATH" && wc -l "$LOG_PATH" && du -h "$LOG_PATH"
```

If the log is empty or smaller than ~1 KB, the run likely aborted before any tool calls. Tell the user this is a host-side failure (auth, image pull, MCP startup) — the agent won't help. Stop.

---

## Step 3: Spawn the Agent

Use the Agent tool with `subagent_type: "ralph-log-doctor"`. Build a self-contained prompt — the agent has no access to this conversation:

```
LOG_PATH: <literal absolute path>
INCLUDE_METRICS: <true|false>
SCOPE: <all|shared-only|repo-only>

Analyse the log per your pattern catalogue. Apply the SCOPE filter. Return the report markdown only — no preamble.
```

The agent is locked to `Bash, Read, Grep, Glob` (read-only) — it cannot modify code or open PRs. That's deliberate.

---

## Step 4: Write the Report (default on)

Unless `--no-write` was passed, write the agent's output to:

```
<dir-of-log>/analysis.md
```

So `tasks/archive/FMFX-12345/ralph-sandbox.log` → `tasks/archive/FMFX-12345/analysis.md`.

If a previous `analysis.md` exists, suffix the new one with a timestamp (`analysis-{YYYYMMDD-HHmm}.md`) — never overwrite. Tell the user the new path.

---

## Step 5: Show & Gate

Display the full report inline. Then use AskUserQuestion:

- **question:** "What next?"
- **options:**
  - "Save the report and stop" *(no-op if --no-write)*
  - "Open PR(s) against `claude-shared/` for the high-leverage fixes" — high blast radius; requires explicit approval
  - "Show me one fix at a time" — walk findings interactively, fix-by-fix, with confirmation per change
  - "Just the report — I'll handle it"

Do **not** open PRs against `claude-shared/` without picking option 2 — it ships to every team using the subtree.

---

## Step 6 (option 2 only): Open PRs

Group findings by **fix home**. One PR per home is usually right (one for `ralph-sandbox/CLAUDE.md`, one for `Dockerfile.sandbox`, etc.) — easier to review and revert.

For each PR:
1. Branch from `main`: `chore/ralph-log-{topic}`
2. Apply the proposed change (Edit the relevant file)
3. Run `git diff --cached --stat` and read it — abort if anything unexpected appears
4. Commit with conventional format including the originating Jira ticket (extract from `prd.json` in the run's archive folder if present)
5. `gh pr create` with the report excerpt as the body

If working on `claude-shared/` directly, push to `FreemarketFX/claude-shared` and link the PR in the consumer repo's PR description.

---

## Edge Cases

- **No `prd.json` in archive folder** — can still proceed; commit message uses `chore` without ticket.
- **User on `main` branch** — never commit to main. Always branch first.
- **Agent returns "log too corrupted to parse"** — relay to user verbatim; offer to inspect manually.
- **Report is huge (>10k tokens)** — write the file but only show the summary inline; tell the user the full report is at `analysis.md`.

---

## Checklist

- [ ] Located the log; got an absolute path
- [ ] Sized the log; aborted on empty/tiny
- [ ] Spawned `ralph-log-doctor` agent with self-contained prompt
- [ ] Wrote report to `<run-dir>/analysis.md` (unless `--no-write`)
- [ ] Showed the report and stopped at the approval gate
- [ ] Opened PRs only on explicit option-2 approval
