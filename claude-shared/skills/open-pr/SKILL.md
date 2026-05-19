---
name: open-pr
description: "Open a pull request with pre-PR checks, hard gates, a standardized description, and explicit commit-strategy selection. Triggers on: open pr, create pr, raise pr, pr ready, ship this, push for review, draft pr."
license: MIT
---

# Open PR

Walks the engineer from a ready branch to an open pull request. Runs pre-PR checks, enforces the hard gates in `.claude/rules/pull-requests.md`, drafts the description in the standardized FMFX format, and creates the PR.

---

## The Job

1. **Detect state** — branch, ticket ID, base branch, staged/unstaged, diff vs base, file inventory.
2. **Run hard gates** — abort if any fail; remediate before continuing.
3. **Offer pre-PR skills** — `/post-ralph`, `/simplify`, `/self-code-review`, `/test-sonar`, `/stylecop-precheck` (if C#), `/risk`, `/security-review` (if relevant).
4. **Pick commit strategy** — squash / rebase / plain push.
5. **Draft PR description** in the standard template, pre-filled.
6. **Open the PR** (draft by default) and offer to hand off to `/pr-build-doctor`.

**Operating mode:** read-only and fast-forward git commands run without prompting (`fetch`, `status`, `log`, `diff`, fast-forward `push`). Every history-rewriting or force-pushing command (`rebase`, `reset`, `merge`, `commit --amend`, `push --force` / `--force-with-lease`) requires an explicit per-invocation confirmation — the skill shows the engineer the exact command line it is about to run and only proceeds on a Yes. Bulk approval ("just do it") is not honoured; one confirmation per destructive command. Confirm the PR title and body before running `gh pr create`.

---

## Shell note

Commands in this skill are written for the Bash tool (POSIX). Run them via the Bash tool, not PowerShell — `grep -E`, `xargs`, and heredocs assume bash semantics. `unix2dos` / `dos2unix` may not exist on stock Windows; if missing, fix line endings with `git add --renormalize <path>` after configuring `.gitattributes`, or rewrite the file with explicit CRLF using PowerShell `[IO.File]::WriteAllText`.

---

## Step 1: Detect State

Run these in parallel (all small output). `<base>` below is the default branch — typically `main`. If `gh repo view` returns a different `defaultBranchRef.name` (rare), re-run the diff/log commands against that base before proceeding.

All comparisons use `origin/<base>` (not local `<base>`) so a stale local default branch can't desync the diff/log/stat outputs. Fetch first:

```bash
git fetch origin <base>                                              # refresh origin/<base> before scans
git rev-parse --abbrev-ref HEAD                                      # current branch
git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>&1            # tracked upstream (may not exist)
git log --oneline -20 origin/<base>..HEAD 2>&1                       # commits on branch
git diff origin/<base>..HEAD --stat                                  # diff-stat vs base
git diff origin/<base>..HEAD --name-only                             # files vs base
git status --porcelain                                               # uncommitted state
gh repo view --json defaultBranchRef,nameWithOwner                   # repo + default base
gh pr list --repo "$(gh repo view --json nameWithOwner -q .nameWithOwner)" \
  --head "$(git rev-parse --abbrev-ref HEAD)" --state all \
  --json number,state,title,url,isDraft,closedAt,headRefName
```

The `--name-only` output from this step is the **file inventory** referenced throughout Step 2 — don't re-invoke `git diff --name-only` per gate; scan the inventory in-memory.

The `gh pr list` output drives **Step 1.5 (existing-PR handling)**. Three cases:

- **Empty array** — no PR has ever existed for this branch; proceed to Step 2 and create a fresh PR in Step 7.
- **One or more entries with `state: OPEN`** — an open PR already exists; this skill should not create a duplicate. Tell the user the PR URL and exit, suggesting `/pr-feedback` or `/pr-build-doctor` instead. The push that landed the new commits has already updated the open PR; nothing more to do here.
- **Entries exist but all are `CLOSED` or `MERGED`** — see Step 1.5.

Derive:

- **Ticket ID** — regex `FMFX-\d+` against branch name. If no match, ask the user. (Required for Conventional Commits scope and PR title.)
- **Base branch** — default branch from `gh repo view`. If branch was cut from a release branch, ask.
- **C# changes?** — any `*.cs` / `*.csproj` in the file list (gates `/stylecop-precheck`).
- **Touches security-sensitive surface?** — any of: `*Auth*`, `*Permission*`, `*Endpoint*`, `*.sql`, `*Secret*`, `appsettings*.json`, `*.bicep`, infra paths. Gates `/security-review` offer.
- **Modified test bodies?** — `git diff origin/<base>..HEAD -- '**/*Tests.cs' '**/*Specs.cs'` for `[Fact]`/`[Theory]` bodies that were edited (not added or removed). Gates the test-rewrite disclosure section.
- **Response-shape changes?** — any `*.Response.cs`, `*Event.cs`, `*.Query.cs`, `*Dto.cs` in the file list. Gates the response-shape disclosure section.

---

## Step 1.5: Existing PRs for this Branch

If Step 1's `gh pr list` returned entries:

### Open PR exists

> "Open PR already exists for `<branch>`: #<num> — \"<title>\" (<draft|ready>). New commits are already pushed; not creating a duplicate."

Then re-run Step 3 (skills the engineer hasn't already run this session), skip Steps 2 and 4–7, and end with the Step 8 handoff. Offer `gh pr ready <num>` if they signal done iterating.

### Closed or merged PR exists (no open PR)

The closed/merged PR stays as-is — `/open-pr` creates a fresh one. Add a `Supersedes #<num> (closed <date>).` line at the top of `## Summary` for reviewer continuity, then proceed normally through Steps 2–7. If the engineer wants to reopen the old PR instead, they should run `gh pr reopen <num>` themselves outside this skill.

---

## Step 2: Hard Gates

These come from `.claude/rules/pull-requests.md`. **Abort the skill** if any fire — remediate and re-run.

Scan the file inventory from Step 1 against each pattern. Patterns below are regex you can apply in-memory; only shell out if the inventory is too large to scan inline.

### 2.1. `tasks/current/` artifacts

Pattern: `^tasks/current/.+`

If anything matches → STOP. Run `/post-ralph` to archive, then re-run `/open-pr`. Never commit `tasks/current/` files (merge-conflict magnet).

### 2.2. Ralph / sandbox artifacts

Pattern: `(^|/)(archive/[0-9]{4}-[0-9]{2}-[0-9]{2}|\.claude/worktrees/)|(^|/)ralph-sandbox\.log$`

If anything matches → ask the user whether it's intentional. Dated archive folders usually belong in a separate PR; sandbox logs should not be committed.

### 2.3. `claude-shared/` subtree edits in a consumer repo

```bash
if [ -f "$(git rev-parse --show-toplevel)/claude-shared/.gitattributes" ]; then
  git diff origin/<base>..HEAD --name-only | grep "^claude-shared/"
fi
```

If anything matches AND we're not in the `claude-shared` repo itself → STOP. These edits belong in a separate PR to `FreemarketFX/claude-shared`.

### 2.4. Diff-stat noise scan

Use the `git diff origin/<base>..HEAD --stat` output already in context from Step 1. Scan every row.

**Only ask the user about rows that look suspicious** — files you didn't touch this session, or where the line-count looks wrong (e.g. 200 lines changed in a file you only edited one line in = line-ending churn). Do NOT iterate through every row asking — that's a spam prompt. For files the agent edited this iteration, skip the ask.

> **Note:** this is a deliberate softening of `pull-requests.md` §Diff-Stat Hard Gate ("scan every row … abort if you don't recognise editing this iteration"). The rule is written for the staging step of a single commit; here it runs once over a multi-commit branch, so asking about every row would spam the user. Files the agent edited in this session are trusted; unfamiliar paths are flagged.

If a row is suspicious, ask once via `AskUserQuestion`:

> "`<path>` shows up in the diff but doesn't look like a change from this iteration. Intentional?"

If the user says no → that's line-ending or whitespace noise. Fix via `git add --renormalize <path>` (preferred, uses `.gitattributes`) or `unix2dos <file>` / `dos2unix <file>` if installed. Re-commit, re-stat. Abort after 2 failed attempts (see `pull-requests.md` §Diff-Stat Hard Gate).

### 2.5. Drive-by changes

Scan the file inventory from Step 1 for paths that don't map to the ticket subject. Drive-by fixes go in their own PR or a clearly labelled separate commit (note in PR description).

**If 0 paths look unrelated → skip the question.** Otherwise issue a single `AskUserQuestion` listing only the flagged paths, asking the user to confirm or split. The question needs ≥2 options; use `Keep all in this PR` / `Split out` (and `Other` is auto-added).

---

## Step 3: Pre-PR Skills Checklist

**Mandatory floor — always offered to the user, never silently skipped:**

- `/self-code-review` — staff review against the rules. Offered as a declinable option.
- `/test-sonar` — semantic coverage / edge-case analysis. Offered as a declinable option.
- `/risk` — **hard-mandatory** per `pull-requests.md`. Always invoked directly via the `Skill` tool; not offered as a declinable option and not surfaced as a question the user can answer "no" to.

**Conditional** (only offered when Step 1 detection flags them):

- `/simplify` — always offered for code changes; skip if Step 1 shows only `*.md` / `*.json` / `*.txt`.
- `/stylecop-precheck` — only if C# changes in Step 1.
- `/security-review` — only if Step 1 flagged security-sensitive surface.

### Asking

Issue **two** `AskUserQuestion` calls, not bundled. Max 4 options per call (`AskUserQuestion max 4 options` rule). Skills already-run in the current session don't need re-offering.

**First call — review/quality skills:**

```
Question: "Pre-PR review — which to run now?"
Header: "Pre-PR"
multiSelect: true
Options (only include those NOT already run this session AND applicable per detection):
  - /self-code-review
  - /simplify
  - /test-sonar
  - /stylecop-precheck   (only if C# in diff)
```

**`/risk` is never offered — invoke it directly via the `Skill` tool before continuing.** Tell the user "Running /risk (mandatory per `pull-requests.md`)."

**Second call — `/security-review` (only if Step 1 flagged sensitive surface):**

`AskUserQuestion` requires a minimum of 2 options, so pair it with another applicable optional skill if possible; otherwise skip the question and invoke `/security-review` directly only if the user has explicitly asked for it. Do NOT bundle `/risk` into this question.

For each option the user selects, invoke that skill via the `Skill` tool before continuing.

### When `AskUserQuestion` is rejected by a hook

If the `enforce-askuserquestion-rules.sh` hook (or any other hook) rejects the batch — typically for `(Recommended)` markers, mixing rule-decided options with genuine ones, or bundling that should be split — **re-issue the question cleanly**: remove the offending marker, split the bundle, drop rule-decided options. **Do NOT silently skip the gate.**

If all attempts to ask still fail, fall back as follows (and surface what's happening to the user in a single message):

- `/risk` — invoke via the `Skill` tool directly. It is mandatory per `pull-requests.md` and there is no user choice to honour.
- `/self-code-review` — invoke directly. Mandatory floor.
- `/test-sonar` — invoke directly. Mandatory floor.
- Any optional skill (`/simplify`, `/stylecop-precheck`, `/security-review`) — skip and list it in the message as "auto-skipped (couldn't prompt); re-invoke manually if wanted: `/<name>`".

The user retains control: they can interrupt and run anything skipped before Step 7.

---

## Step 4: Commit Strategy

### Confirmation rules

| Command | Action |
|---------|--------|
| `git fetch`, `status`, `log`, `diff` | Run (read-only) |
| `git push` fast-forward (incl. `-u origin <branch>` first push) | Run |
| `git rebase origin/<base>`, `git reset --soft`/`--mixed`, `git commit --amend`, `git merge`, `git push --force-with-lease` | **`AskUserQuestion` per invocation, literal command quoted in the option label.** No bundling — one Yes per command. |
| `git push --force` bare, `git rebase -i`, `git add -i`, `git reset --hard`, `git stash drop`, `git branch -D`, `git clean -fd` | **Refuse.** Print the command + one-line reason; engineer runs it themselves outside the skill. |

The confirmation prompt must quote the literal command line, branch name, and upstream ref — never paraphrase. The shape:

```
Question: "Run `<exact command>` on `<branch>`? <one-line consequence>"
Options:
  - "Yes, <verb>"
  - "No, stop"
```

### Ask the strategy

```
Question: "How should we handle commits before pushing?"
Header: "Strategy"
multiSelect: false
Options:
  - "Plain push (commits as-is)"             — fast-forward push; no confirm
  - "Rebase onto base, then push"            — rebase + force-push; 2 confirms
  - "Squash + rebase to one commit on base"  — rebase + reset + commit + force-push; 4 confirms
  - "Squash via GitHub merge button"         — fast-forward push; squash happens at merge time
```

### Per-strategy flow

- **Plain push.** `git fetch origin <base>` then `git status -uno`. Ahead-only → `git push`. Behind base → STOP, offer the rebase path. Diverged from upstream → STOP, ask the engineer to pick `git pull --rebase` or `git push --force-with-lease` (the pick is the per-command confirmation).
- **Rebase onto base.** Fetch, then confirm `git rebase origin/<base>`. On Yes, run (never `-i`); on conflict, STOP and print the recovery commands (`git rebase --abort` / `--continue`) — never auto-resolve. On success, confirm `git push --force-with-lease` separately.
- **Squash + rebase to one commit on base.** Fetch, confirm rebase (as above), then confirm `git reset --soft origin/<base>`. Draft the Conventional Commits squash message per §5.1 and show it. Confirm `git commit -F <draft-msg-file>` (offer "edit the message" option). Finally, confirm `git push --force-with-lease` separately — engineer must be able to inspect the local result before the force-push lands.
- **Squash via GitHub merge button.** No local rewrite. Fast-forward `git push` only. PR title MUST be Conventional Commits compliant (§5.2) — that's what the merge will use.

---

## Step 5: Conventional Commits + Trailer (org rule)

Both commit messages AND the PR body MUST follow these org-level rules (non-negotiable):

### 5.0. Trailer — substitute the current model ID

The org trailer is:

```
Co-Authored-By: Claude (<MODEL_ID>) <noreply@anthropic.com>
```

`<MODEL_ID>` is the API ID of the Claude model currently invoking this skill — e.g. `claude-opus-4-7`, `claude-sonnet-4-6`, `claude-haiku-4-5-20251001`. **Substitute the actual running model ID** — never emit the literal `<MODEL_ID>` placeholder, and never hardcode a specific ID in the skill output. If the running model genuinely cannot determine its own ID, omit the parenthetical: `Co-Authored-By: Claude <noreply@anthropic.com>`.

### 5.1. Commit format

```
<type>(<scope>): <subject>

<body>

Co-Authored-By: Claude (<MODEL_ID>) <noreply@anthropic.com>
```

- `<type>`: one of `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`
- `<scope>`: the Jira ticket ID, e.g. `FMFX-16130`
- `<subject>`: imperative, lowercase, no trailing period
- Breaking change: `!` after scope AND a `BREAKING CHANGE:` footer
- Trailer: blank line then the Co-Authored-By line per §5.0 (substitute the running model ID).

If the user's existing commits don't comply and the chosen strategy is plain push, surface the violation and ask whether to rewrite (non-interactive `git rebase --exec` or amend the latest commit). Don't silently rewrite history.

> **Format precedence:** these org-level Conventional Commits rules override the simpler shape in `.claude/rules/pull-requests.md`. When the two diverge, follow this skill. Consumer repos should align `pull-requests.md` over time.

### 5.2. PR title

Same Conventional Commits shape:

```
<type>(FMFX-XXXXX): <subject>
```

### 5.3. PR body trailer

Last line of the PR body must be the Co-Authored-By line per §5.0 (with the running model ID substituted):

```
Co-Authored-By: Claude (<MODEL_ID>) <noreply@anthropic.com>
```

Preceded by a blank line.

---

## Step 6: Draft the PR Description

Use this template. Pre-fill from context; ask the user to fill the blanks.

```markdown
## Summary

<2–6 bullets or short prose. What the PR does and why. Link the Jira ticket inline:
[FMFX-XXXXX](https://freemarket.atlassian.net/browse/FMFX-XXXXX).>

## Test plan

- [x] <command that ran, e.g. `dotnet build` — 0 warnings, 0 errors>
- [x] <unit/integration test command — N/N passed>
- [ ] <CI-only items the user can't run locally>

## Risk Assessment

**Risk Category:** <LOW | MEDIUM | HIGH | CRITICAL>

| Dimension | Result | Reason |
|-----------|--------|--------|
| Customer/Business | <Yes/No> | <one line> |
| System/Architecture | <Yes/No> | <one line> |
| Data/Security | <Yes/No> | <one line> |
| Operational/Delivery | <Yes/No> | <one line> |

**Mitigations:**
- <bullet per mitigation>

Co-Authored-By: Claude (<MODEL_ID>) <noreply@anthropic.com>
```

(Substitute `<MODEL_ID>` with the running model's API ID per §5.0.)

### Conditional sections — add only when applicable

**Context** (between Summary and Test plan) — when the *why* needs more than a Summary bullet:

```markdown
## Context

<paragraph or bullets explaining the broader change, dependencies, or PRD reference.>
```

**Out of scope** (after Risk Assessment) — when reviewer might expect related work in this PR:

```markdown
## Out of scope

- <thing deliberately not done in this PR — link to follow-up ticket if known>
```

**Implementation note** (between Summary and Test plan) — when a deviation from rules/PRD needs justification:

```markdown
## Implementation note: <topic>

<paragraph explaining why this approach diverges from the prescribed pattern.>
```

**Test rewrites** (after Test plan) — REQUIRED if Step 1 detected modified test bodies. Required per `pull-requests.md` §Test-Body Rewrites:

```markdown
## Test rewrites

- `ClassName.TestMethodName` — <invariant the new body asserts>
```

**Response-shape change** (after Risk Assessment) — REQUIRED if Step 1 detected changes to `*.Response.cs`, `*Event.cs`, `*.Query.cs`, `*Dto.cs`. Required per `pull-requests.md` §PR Hygiene:

```markdown
## Response-shape change

Affected DTOs/events: <list>. Related endpoints/consumers aligned in this PR: <list> — OR — Follow-up PR aligning <list>: <ticket>.
```

### Risk category

`/risk` is hard-mandatory (Step 3) — use its output verbatim. Copy the full table into the PR body; don't redraft.

---

## Step 7: Open the PR

### 7.1. Confirm before creating

Show the user the final title and body. Ask:

```
Question: "Open the PR now?"
Options:
  - "Yes, open as draft (default)"
  - "Yes, open as ready for review"
  - "Let me edit the description first"
  - "Cancel"
```

Default to draft — flips to ready-for-review when CI is green and the user is satisfied. Save the user from a premature "needs review" notification storm.

### 7.2. Create

Omit the `--draft` flag if the user picked "ready for review":

```bash
gh pr create \
  --base <base-branch> \
  --title "<conventional-commits-title>" \
  --body-file <draft-body-file> \
  --draft
```

**Always use `--body-file`** with a heredoc / temp file. Never pass body via `--body "..."` — quoting on Windows PowerShell drops markdown formatting silently.

### 7.3. Labels

If `/risk` produced a category, attempt to apply the matching label and swallow the error if the label doesn't exist (don't pre-check, don't create):

```bash
gh pr edit <pr-number> --add-label "risk:<category>" 2>/dev/null || true
```

### 7.4. Reviewers

GitHub auto-assigns from `CODEOWNERS` server-side. Don't manually `--reviewer` unless the user asks.

---

## Step 8: Post-Create Handoff

Return the PR URL and offer `/pr-build-doctor <pr-number>` to watch CI. If the engineer wants to re-run any Step 3 skill against the rendered PR, they can invoke it directly.

---

## Safety Rails

Step 4 covers the confirmation/refusal table. Additional rules:

- **Never** force-push to `main` or other shared / protected branches, even with confirmation. `/open-pr` only operates on PR-feature branches.
- **Never** skip hooks (`--no-verify`) or signing — fix the underlying failure.
- **Never** commit files containing secrets (`.env`, `credentials.json`, `*.pem`). If any are staged, refuse and surface.
- **Never** call `gh pr create` before Step 7.1 confirmation.

---

## Inputs

This skill takes no arguments. Run as `/open-pr` from the branch you want to PR.

## Outputs

- PR URL (final).
- The drafted description is passed to `gh pr create --body-file` via an **absolute Windows path inside the repo root** (e.g. `<repo-root>/.pr-body.md`). Delete the file on success. Never use `/tmp` on Windows — Bash `/tmp` and Write-tool `/tmp` resolve differently and `gh pr create` silently picks up the wrong file. Add `.pr-body.md` to `.gitignore` if not already covered, or use a name that's already ignored.
