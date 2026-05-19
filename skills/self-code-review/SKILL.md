---
name: self-code-review
description: "Review branch changes against main as a principal/staff engineer. Performs deep analysis of correctness, architecture, security, and maintainability. Triggers on: review code, code review, review my changes, review this branch, staff review, principal review."
license: MIT
---

# Principal Engineer Code Review

Review all changes on the current branch against main, providing the kind of thorough, opinionated feedback a principal or staff engineer would give.

---

## The Job

1. Identify the current branch and gather the full diff against main
2. Understand the intent of the changes from commit history
3. Load review rules from CLAUDE.md / MEMORY.md / `.claude/rules/`
4. **Enumerate adversarial inputs *before* reading the implementation** (counters author bias)
5. **Enumerate sibling guards** when an obvious sibling exists (no vibe-checks)
6. Analyse changes across six review dimensions, including a **pair-disagreement walk** for handlers that combine request data with loaded entities
7. Output a structured review with findings ranked by severity, treating documented rule violations as un-downgradable
8. Provide a final verdict
9. On auto-fix, **re-scan the modified surface after each round** before committing

**Mindset:** You are a principal/staff engineer reviewing this code before it ships to production. You care deeply about correctness, long-term maintainability, and the health of the codebase. You are direct, constructive, and specific. You don't nitpick formatting — you focus on things that matter.

**Author bias is the dominant failure mode of self-review.** The author has a mental model of intent, so they trace happy paths and miss hostile inputs. The adversarial-input enumeration (Step 2.6), sibling-guard enumeration (Step 2.7), and pair-disagreement walk (in Dimension 1) exist to invert that bias structurally. Skip them at your peril.

---

## Step 1: Gather Context

**Important:** Never run `git diff` or `gh pr diff` directly in Bash — large output stalls the review via PostToolUse hooks. Always write the diff to a temp file and use the Read tool, which handles chunking via `offset`/`limit`.

Run these (all safe, small output):

```bash
gh --version 2>&1                                          # is gh available?
git rev-parse --abbrev-ref HEAD                            # current branch
gh pr view --json number,title,body,url,labels,baseRefName,additions,deletions,changedFiles 2>&1
gh pr checks 2>&1
gh pr diff --name-only 2>&1                                # file list
gh api repos/{owner}/{repo}/pulls/{pr_number}/comments --jq '.[] | "(@\(.user.login)): \(.body[0:200])"'
```

Then write the full diff to a file for the Read tool:

```bash
gh pr diff > /tmp/pr-review-diff.txt 2>&1                  # or: git diff main...HEAD
```

If `gh` is unavailable or no PR exists, fall back to `git log main..HEAD --oneline`, `git diff main...HEAD --stat --name-only`, and the same file-then-Read pattern for the diff body.

### No PR yet? Offer a draft

This skill is most useful *after* a PR exists — it can read title/body, CI status, and existing review comments, and post findings inline afterwards. If `gh pr view` reports no PR for the branch, ask the user whether to create a draft first:

> *"No PR exists for this branch. Create a draft now so the review picks up title/body, CI status, existing reviews, and can post findings inline? (yes / no)"*

On **yes**: run `gh pr create --draft` with a title derived from the latest commit subject and a body derived from the branch's commit messages, then re-run Step 1 against the new PR.

On **no**: proceed with the git-only fallback below. Note: *Post as PR comment* in Step 6 will be unavailable.

---

## Step 2: Understand Intent

Before reviewing code, understand what the author was trying to accomplish. Read commit messages, PR title/body/labels, CI status, and any existing review comments (so you don't duplicate feedback). Summarise in one paragraph.

If prior reviewers have commented, note it:
```
**Prior review feedback:** [N] comments from [reviewers] — read, will not duplicate.
```

---

## Step 2.5: Load Review Rules

Load the project's coding standards as an explicit checklist:

1. **Find CLAUDE.md**: `Glob("CLAUDE.md")` from repo root. If not, `Glob("**/CLAUDE.md")` and take the first match outside `claude-shared/`, `node_modules/`, or `.claude/`.
2. **Extract checklist**: Look for a "Common Review Feedback" section — each bullet is a checkpoint. Also read Testing, Code Style, and Architecture sections.
3. **Check MEMORY.md**: `Glob("MEMORY.md")` from repo root. Read `feedback`-type entries if found.
4. **Severity floor**: Any finding matching a CLAUDE.md or MEMORY.md rule is **SHOULD FIX minimum**, never CONSIDER.

### Standing Checkpoints

Pattern-match the diff against these triggers — when one fires, investigate. Rule bodies live in the repo's `CLAUDE.md` (synced from `claude-shared/CLAUDE_TEMPLATE.md`); the skill tells you *when* to look, the template tells you *what* the rule is. Any finding matching a Standing Checkpoint is **SHOULD FIX minimum**.

These are not a tick-list. Treat them as "when I see X, check Y" — investigate only what the diff actually touches.

#### Diff hygiene (run first — self-contained, not in CLAUDE.md)

- Every file in `git diff main..HEAD --name-only` must map to an AC line or commit message. Flag drive-bys.
- Flag edits inside `claude-shared/` — git subtree, PRs separately to the claude-shared repo.
- Flag files under `tasks/current/` — archive via `/post-ralph` before PR.
- Flag dated archive folders (e.g. `tasks/archive/2026-MM-DD-<ticket>/`) duplicating an existing `tasks/archive/<ticket>/` for the same work.

#### SQL migrations → `**/Migrations/Scripts/**.sql`

Multi-step migrations without `GO` batch separators; system-versioning toggles that aren't independently idempotent. → see the SQL migration rules in CLAUDE.md.

#### Change-feed handlers → `*ReadModelHandler.cs`, `*ChangedReadModelHandler.cs`, `DomainEventHandler<Changed<T>>`

Re-run-unsafe INSERTs (no `WHERE NOT EXISTS` / `MERGE`); `Get<T>` + null check (use `MaybeGetById<T>` + `Switch` — `Get<T>` throws on 404, null check is dead code). → see the change-feed / idempotency rules in CLAUDE.md.

#### Validators → `*Validator.cs`

String ops (`.ToUpper*` / `.ToLower*` / `.Trim` / `.Split` / `.StartsWith` / `.Length`) on a request field without a `.When` / `.Where` null guard; ≥80% duplication with an existing validator. → see the validator rules in CLAUDE.md.

#### Endpoints → `*.Endpoint.cs`

PUT not returning `SuccessWithVersion<T>` + ETag header + 412 in `ProducesProblems`; `.ProducesProblems()` codes not matching return type; inconsistency across analogous endpoints on the same resource; forward-declared `EndPointNames.*` or `*.Link.cs` records. → see the endpoint rules in CLAUDE.md.

#### Permissions → `Permissions.cs`, `*RolePermissions*.sql`, `RoleToPermissionsMap.cs`

Permission add/rename/remove not touching all three locations; SQL/C# count drift; new permissions with no `HasPermission(...)` consumer in the diff. → see the permission rules in CLAUDE.md.

#### HATEOAS → `*.Link.cs`, handlers returning a `HateoasResource` subclass

CRUD link parity missing; `Rel` collisions on the same resource; `Link.cs` records never emitted anywhere. → see the HATEOAS rules in CLAUDE.md.

#### Tests → `**/test/**/*.cs`

401/403 tests using `Guid.NewGuid()` for the target resource; local response DTOs when source DTOs exist; helpers/fakes already in `Tests.Shared/`; `DisposeAsync` missing `cosmosFixture.ResetRepository<T>` / `sqlFixture.ResetDb()`; OpenAPI `[Description]` attrs not matching FluentValidation limits; BDD tests starting with `And(...)` instead of `Given`. → see the test rules in CLAUDE.md.

#### Response shape consistency → DTO / event / aggregate shape change

Divergent fields/types across `*.Response.cs`, `*Event.cs`, `Get*.Query.cs` on the same resource — unless the PR explicitly defers alignment to a named later PR. → see the response-shape / PR-hygiene rules in CLAUDE.md.

#### Test-body rewrites → any modified `[Fact]` or `[Theory]` body in the diff (not added or removed)

For each test method whose body changed:

1. Compare what the *old* body asserted (via `git diff`) to what the new body asserts.
2. Flag if the new body: is meaningfully shorter, delegates to another existing test method (`MethodName();` as the entire body), or no longer aligns with the test name's verb (`EachHas*`, `*Distinct*`, `*Per*`, `*Throws*`, `*Returns*`).
3. Severity: **SHOULD FIX** at minimum. Restore the original invariant against the new code shape, or rename / delete the test. A test whose name lies about what it asserts presents as coverage in CI and degrades the diagnostic value of the suite.
4. Heuristic that mechanically catches most cases: the test name contains a comparison verb (`Distinct`, `EachHas`, `Per`, `Two`) but the body has no `BeEquivalentTo` / `NotBeSameAs` / `Should().Be(<other instance's value>)` style assertion comparing two resolved values.

→ see the test-body-rewrites rule in `.claude/rules/pull-requests.md`.

If a trigger fires but the loaded CLAUDE.md doesn't cover it, flag the finding with the rule-gap noted ("rule missing from CLAUDE.md") and fall back to the six-dimension review for that file.

---

## Step 2.6: Adversarial Input Enumeration (BEFORE reading the implementation)

**The author is the wrong reviewer of their own code.** They have a mental model of intent, so they trace happy paths and miss hostile inputs. To counter this, enumerate adversarial scenarios *before* opening the implementation files.

For each new endpoint, command handler, validator, or DTO surface in the diff, list 8–12 ways a malicious user, typo-prone operator, or confused integrator would try to break it. Categories to enumerate:

- **Wrong-case identifiers / enum codes** — string identifiers that case-mismatch what the code expects
- **Configuration typos** — config keys whose value is a scope or environment identifier (e.g. a key intended for environment A points at environment B's resource ID)
- **Cross-scope references** — a request supplying an entity ID that belongs to a different tenant / customer / workspace / region than the request's declared scope
- **Cross-grouping references** — an entity belonging to a different parent / collection / partition than the one the endpoint operates on
- **Wrong-type references** — an ID of one entity type where another is expected (e.g. a "Company" entity ID where "Individual" is required)
- **Stale references** — IDs of soft-deleted, archived, suspended, or retired entities
- **Empty / whitespace string fields** that pass `NotEmpty` / `required` but break business logic
- **Negative / zero / boundary numerics** — limits, page sizes, counts
- **Retry storms / double-click** — same request submitted twice, race conditions, missing idempotency
- **Permission changes mid-request** — caller has a role at request time that's revoked before completion (or vice versa)
- **Validator/handler drift** — fields the validator marks as required but the handler doesn't read, or fields the handler depends on but the validator doesn't enforce
- **Trailing / leading whitespace** in identifiers used as keys, lookups, or natural keys

The repo's local `CLAUDE.md` (especially any "Common Review Feedback" section) often lists scenarios that have bitten this codebase before — read those as additional adversarial seeds.

Hold this list while reading the implementation. For each adversarial input, find the line that catches it. **Unhandled adversarial inputs that produce 500/silent-success → MUST FIX. Adversarial inputs that produce a generic error instead of a clear 4xx → SHOULD FIX.**

Doing this *before* reading the implementation inverts the author bias: you arrive at the code with a checklist of disagreements to find, rather than a story of intent to confirm.

---

## Step 2.7: Sibling-Guard Enumeration (mandatory when a sibling exists)

When the new code has an obvious sibling — same folder, same naming pattern, same domain (e.g. a new handler/validator/endpoint added next to an existing one for a closely related operation) — **enumerate every guard in the sibling and verify the new code has the equivalent**.

Sibling-as-vibe-check is a known failure mode: "matches sibling pattern" is satisfying to write but is false unless you've counted. Operationalise it:

1. Identify the closest sibling by name pattern and folder location.
2. Read it in full.
3. List every:
   - Conditional guard that short-circuits to an error result
   - Result / status assignment (success vs. each error type)
   - Domain-invariant check (entity-state checks, scope-equality checks, type checks)
   - Authorization / permission check
4. For each entry, decide: does the new code need an equivalent? If not, articulate why.
5. **Missing equivalents → SHOULD FIX minimum.** Often MUST FIX (cross-scope bleed, wrong-type acceptance, missing authorization check).

If the sibling itself violates a documented rule, that's a *separate* finding to raise on the sibling — don't use it as a license to violate the rule in the new code.

---

## Step 3: Review Across Six Dimensions

Work through the diff systematically. Skip any dimension with nothing to report.

### 1. Correctness & Logic
Logic errors, off-by-one bugs, unhandled edge cases (nulls, empty collections, boundaries, concurrency). Does the code match the claimed intent? Any race conditions or silently-swallowed failures?

**Pair-disagreement walk (mandatory for any handler combining request data with loaded entities):**

List every pair of typed values of the same domain (scope identifiers, parent IDs, type codes, owner IDs) the handler touches. Sources to consider:

- Values supplied by the request (DTO fields)
- Values resolved from configuration (lookups, resolvers, options)
- Values loaded from the repository (entity properties)
- Values derived from authentication / authorization context (caller's tenant, caller's owner, etc.)

For each pair, ask: *should they agree?* In almost all cases, yes — they describe the same scope. Then find the line that enforces the agreement.

Build a table per handler. Generic shape:

| Pair | Should agree? | Enforced at |
|------|---------------|-------------|
| `request.{scope}` vs. loaded entity's `{scope}` | Yes — cross-scope bleed otherwise | line N or **MISSING** |
| `request.{scope}` vs. configured resource's `{scope}` | Yes — config drift otherwise | line N or **MISSING** |
| `configured.{parentId}` vs. loaded entity's `{parentId}` | Yes (if endpoint operates on a fixed parent) | line N or **MISSING** |
| `request.{entityId}` and loaded entity's `Type` | Type must match the endpoint's contract | line N or **MISSING** |
| Caller's authorized scope vs. request's declared scope | Yes — privilege escalation otherwise | line N or **MISSING** |

**A "MISSING" row is a cross-scope / cross-owner / cross-type bleed. Default severity: SHOULD FIX. Promote to MUST FIX if it crosses a security, privacy, or regulatory boundary** (tenant isolation, customer data segregation, role enforcement, etc.).

The repo's local `CLAUDE.md` may list specific identifier pairs that have caused incidents in this codebase — those are the highest-priority rows to verify.

### 2. Architecture & Design
Does this fit the existing architecture or fight it? Abstractions at the right level? Premature abstraction, over-engineering, or unwarranted coupling? Would it hold up under minor requirement changes?

### 3. Security
Injection risks (SQL, command, XSS). User input validated at trust boundaries. Secrets / credentials / PII handled safely. Auth checks present and correct on new API surface.

### 4. Performance & Scalability
N+1 queries, unbounded loops, large in-memory collections, missing indexes, blocking I/O. Would this degrade under 10x traffic?

### 5. Testing
Adequate coverage. Tests verify behaviour, not implementation mirrors. Edge cases and error paths covered. Test names describe what they verify.

### 6. Maintainability & Readability
Clear intention-revealing names. No magic numbers or duplicated logic. Complex rules explained. Follows existing conventions.

---

## Step 4: Classify Findings

- **MUST FIX** — Bugs, security vulnerabilities, data-loss risks, correctness issues. Don't merge without addressing.
- **SHOULD FIX** — Design issues, missing tests for important paths, performance concerns. Strongly recommended before merge. Every finding matching a CLAUDE.md, MEMORY.md, or Standing Checkpoint rule lives here at minimum.
- **CONSIDER** — Suggestions. Code works, could be cleaner. Author's discretion.
- **PRAISE** — Good patterns, clever solutions, clean refactoring. Principal engineers notice good work too.

### Rule violations are absolute

If a finding matches a documented MUST/SHOULD rule (CLAUDE.md, MEMORY.md, an `endpoints.md` / `change-feed.md` / `validators.md` rule under `.claude/rules/shared/`, or a Standing Checkpoint), severity is **fixed by the rule keyword**. Do **not** downgrade for any of:

- **"Matches sibling pattern"** → if the sibling violates the same rule, that's a *separate* finding to raise on the sibling. Sibling drift is not license.
- **"Would hurt readability"** → the rule's own rationale already weighed alternatives. If the rule is wrong, fix the rule, not this PR.
- **"Behaviour is currently correct"** → most rules exist to prevent *future* regressions, not present bugs. The current behaviour passing is irrelevant.
- **"Author taste"** → the author's taste is the lowest-priority input on a documented invariant.

If you find yourself wanting to downgrade a rule violation, that's a signal to *upgrade* the finding, not soften it: write a paragraph in the finding explaining the temptation and why the rule still applies. Reviewers can then challenge that paragraph specifically. This makes the rationalization visible instead of hidden.

---

## Step 5: Output the Review

```markdown
## Code Review: [branch-name]

**Reviewer:** Principal/Staff Engineer (AI)
**Branch:** [branch] → main
**Commits:** [N] | **Files:** [N] | **Lines:** +[added] / -[removed]
**CI Status:** [passing/failing/pending]
**PR:** [#number URL]

### Understanding
[1 paragraph on what these changes do and why]

---

### Findings

#### MUST FIX

> **[Short title]**
> `path/to/file.cs:42`
>
> [What's wrong and why it matters]
>
> **Suggestion:** [How to fix]

[Repeat for each finding]

#### SHOULD FIX
[Same format]

#### CONSIDER
[Same format]

#### PRAISE
[Brief callouts of good work]

---

### Summary

| Category   | Count |
|------------|-------|
| Must Fix   | X     |
| Should Fix | X     |
| Consider   | X     |
| Praise     | X     |

### Verdict

**[APPROVE / REQUEST CHANGES / NEEDS DISCUSSION]**

[1-2 sentence assessment]
```

**Verdict criteria:**
- APPROVE — No MUST FIX, at most minor SHOULD FIX. Ship it.
- REQUEST CHANGES — MUST FIX items or multiple significant SHOULD FIX items.
- NEEDS DISCUSSION — Architectural / direction questions, not code quality.

---

## Step 6: Next Steps

Ask the user what they'd like to do next.

**If `gh` is available and a PR exists:**
```
A. Post this review as a PR comment (Recommended)
B. Ask one issue at a time if I should fix it
C. Auto-fix MUST FIX and SHOULD FIX items
D. Discuss architectural/design findings
E. Nothing — I'll handle it from here
```

**Option A — Post as PR comment:**

Post the full review as a single PR comment using `gh`:

```bash
gh pr comment --body "$(cat <<'EOF'
[Full review output from Step 5]
EOF
)"
```

If there are MUST FIX or SHOULD FIX findings, also post inline comments on the specific files/lines:

```bash
# For each finding with a specific file and line
gh api repos/{owner}/{repo}/pulls/{pr_number}/comments \
  -f body="[Finding description and suggestion]" \
  -f path="path/to/file.ts" \
  -f commit_id="$(gh pr view --json headRefOid -q '.headRefOid')" \
  -f line=42 \
  -f side="RIGHT"
```

**Option B — Ask for each issue:**

Ask the user 1 by 1 if they want to fix each issue directly. If they say yes then read each affected file, apply the suggested fixes, and show the changes for approval before committing.

**Option C — Auto-fix:**

Attempt to fix MUST FIX and SHOULD FIX items directly. Read each affected file, apply the suggested fixes, and show the changes for approval before committing.

**After each round of fixes, re-scan the modified surface before committing.** A single-pass review at end-of-branch is structurally insufficient: fixes can introduce new asymmetries (e.g. fixing a case-sensitivity bug on one side of a value while leaving the other side unchanged), new rule violations (e.g. extracting a helper that now violates a naming convention), or new unhandled adversarial inputs the fix exposed.

Re-scan checklist (apply only to lines/files touched by the fixes):

- **New asymmetries on the same value:** the fix changed one comparison/lookup/normalization — does the other side of the same value still match? Search the diff for the value name.
- **New rule violations:** does the fix introduce any pattern the standing checkpoints would flag? (e.g. raw `INSERT` instead of `MERGE`, `Get<T>` + null check, untested permission gate)
- **New adversarial inputs:** does the new branch expose a hostile path that the original code didn't have? (e.g. a new validator rule whose error path needs a 422 test)
- **Test parity:** every behavioural fix needs a test that fails without it. Without the test, the fix can regress silently.

If any re-scan finding fires, treat it as a fresh review iteration — fix it, then re-scan again. Only commit when the modified surface is clean.

**Option D — Discuss:**

Open a conversation about the architectural or design findings. Explain the trade-offs and help the author decide on the right approach.

**If `gh` is NOT available:**
```
A. Auto-fix MUST FIX and SHOULD FIX items (Recommended)
B. Discuss architectural/design findings
C. Nothing — I'll handle it from here
```

---

## Step 7: Update Progress Log (if applicable)

If `Glob("tasks/current/progress.txt")` returns a match, **append** (never replace) a review entry so Ralph and future iterations see the feedback:

```
## [Date/Time] - Code Review
- Principal review of branch [branch]
- Verdict: [APPROVE / REQUEST CHANGES / NEEDS DISCUSSION]
- Findings: [N] must fix, [N] should fix, [N] consider, [N] praise
- Key issues: [one line per MUST/SHOULD FIX]
- Learnings for future iterations: [patterns, gotchas, context]
---
```

If the file doesn't exist, skip.

---

## Review Principles

- **Be specific.** Not "this could be better" — exactly what's wrong and how to fix.
- **Focus on impact.** A missing null check on a payment path beats a suboptimal variable name.
- **Assume competence.** If something looks wrong, consider whether you're missing context before flagging.
- **One problem, one finding.** Don't lump issues.
- **Praise matters.** Recognising good patterns reinforces them.
- **Don't rewrite the PR.** Flag and suggest direction, don't provide full replacement implementations unless it's a small, clear fix.
- **Direct but respectful.** The author reads this.

---

## Edge Cases

**Very large diffs (50+ files):** Triage via `--name-only` and `--stat` first. Read the diff in chunks using Read tool `offset`/`limit`. Prioritise: API/contract changes, business logic, data layer, security-sensitive areas. Skim or skip: generated files, lock files, test fixtures, trivial config entries. State which files you focused on.

**Diff output stalls:** If Bash output truncates or a hook interrupts, the diff was too large for Bash. Don't retry — write to file (`git diff main...HEAD > /tmp/pr-review-diff.txt 2>&1`) and use the Read tool.

**No changes:** If the diff is empty: `No changes found between this branch and main. Nothing to review.`

**Branch diverged from main:** Note it, review what's on the branch anyway.

---

## Checklist

Before outputting the review:

- [ ] Checked if `gh` CLI is available and used it if so
- [ ] Read the full diff (or prioritised subset for large PRs)
- [ ] Understood the intent from commits/PR description
- [ ] Checked for existing review comments (if `gh` available) to avoid duplicating feedback
- [ ] Noted CI/check status (if `gh` available)
- [ ] **Loaded CLAUDE.md / MEMORY.md / `.claude/rules/` rules as the severity floor**
- [ ] **Enumerated adversarial inputs BEFORE reading the implementation (Step 2.6)**
- [ ] **Enumerated sibling guards (Step 2.7) when a sibling exists**
- [ ] Reviewed across all six dimensions
- [ ] **Performed the pair-disagreement walk for any handler combining request data with loaded entities**
- [ ] Classified every finding by severity, **without downgrading rule violations**
- [ ] Included file paths and line references for each finding
- [ ] Provided actionable suggestions, not just complaints
- [ ] Gave praise where deserved
- [ ] Delivered a clear verdict
- [ ] Offered next steps (post to PR, auto-fix, or discuss)
- [ ] **On auto-fix: re-scanned the modified surface after each round of fixes (Option C)**
- [ ] Updated `tasks/current/progress.txt` if it exists
