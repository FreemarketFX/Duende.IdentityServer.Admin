---
name: test-sonar
description: >
  Semantic test coverage analysis beyond line metrics. Identifies gaps between executed code
  and verified behavior. Produces adversarial/edge-case tests, detects rot, scores confidence.
  Invoked by: test coverage, test gaps, edge cases, mutation testing, test quality.
argument-hint: "focus (name, path, or glob), or flags: --diff --rot --mutation --no-response-shape"
license: MIT
---

# Test Sonar

Transforms "did we run this code?" into "do we actually *understand and verify* what this code does?"

## Core Philosophy

Line coverage is a vanity metric. A test that calls a function but asserts nothing gives 100% line coverage and zero confidence. This skill operates on **semantic coverage**: mapping the behaviours your code implicitly promises against the behaviours your tests actually verify.

There are four coverage dimensions that matter:

1. **Behavioural** — are all code branches and outcomes tested?
2. **Adversarial** — are edge cases, boundaries, and malformed inputs tested?
3. **Mutation** — do tests actually *catch* bugs, or just run code?
4. **Temporal** — are tests still verifying the right things after refactors?

---

## Scope Resolution

Determine what to analyse from `$ARGUMENTS`:

| Argument | Scope |
|----------|-------|
| A focus term (bare name, no path separators) | Resolved via fuzzy directory search (see below) |
| A directory path | That directory and its subdirectories |
| A file path | That file only |
| A glob pattern (e.g., `src/**/*.service.ts`) | All matching files |
| `--diff` | Files changed on the current branch vs main |
| No argument | Files changed on the current branch vs main (default) |

**Focus term resolution:** When the argument is a bare name (no `/` or `\`), search the project for matching directories:
1. Search for directories whose name matches or contains the term (case-insensitive)
2. Prefer source directories over test/build/output directories (exclude `node_modules`, `bin`, `obj`, `dist`, `.git`, etc.)
3. If multiple matches exist, include all of them (e.g., a focus of `auth` might match both `src/Auth/` and `lib/auth-utils/`)
4. Use the project's test-to-source mapping (resolved in Phase 1b) to automatically include corresponding test directories
5. If no directory matches, fall back to treating the term as a file path

This allows concise, project-agnostic invocations like `/test-sonar auth` or `/test-sonar payments --mutation` — the skill discovers the right directories regardless of project structure.

**Optional flags** (can be combined with any scope):
- `--rot` — also run Phase 6 (Test Rot Detection)
- `--mutation` — also run Phase 5 (Mutation Validation)
- `--no-response-shape` — skip the HTTP response-shape sub-phase (Phase 3b). Default is ON.

**Fallback when scope resolves to nothing** (no diff, no argument): Do NOT analyse the entire codebase. Instead, use progressive deepening:
1. Start with files modified in the last 10 commits on the current branch
2. If that yields nothing, analyse the most recently modified source directory
3. Only expand further if the user explicitly requests full-codebase analysis

**Scope size limits:** If the resolved scope exceeds 15 source files, process in batches of 10-15 files. Produce a per-batch Semantic Coverage Report as you go, then a rollup summary at the end. This prevents quality degradation on large modules. Present each batch report to the user before proceeding to the next batch.

---

## Workflow

### Phase 1 — Reconnaissance

Read the codebase to understand the scope. Do NOT ask the user — resolve scope from `$ARGUMENTS` using the rules above.

**1a. Detect project conventions:**
- Read CLAUDE.md (if present) for explicit test conventions
- Identify the language, test framework, assertion library, and mocking library from project config files (`package.json`, `*.csproj`, `go.mod`, `pyproject.toml`, `Cargo.toml`, etc.)
- Find the test run command (from CLAUDE.md, `scripts` in package.json, Makefile, etc.) — store this for Phase 4 verification
- Check whether the project currently builds cleanly by running the build command (if identifiable). Store the result: `build_clean = true/false/unknown`. This determines whether Phase 4 verification is attempted.

**1b. Resolve test-to-source mapping:**
Determine how the project maps source files to test files. Check for these common patterns in order:
- **Co-located**: test files next to source (`foo.test.ts`, `foo_test.go`, `foo.spec.js`)
- **Mirror directory**: a `tests/` or `__tests__/` tree that mirrors `src/` structure
- **Convention-based**: test files named after source files with a suffix/prefix (`TestFoo.java`, `test_foo.py`)
- **Flat**: all tests in a single directory with naming conventions

Verify the mapping by checking that at least one source file in scope has a corresponding test file. If the mapping is ambiguous, check 3-4 test files to confirm the pattern before proceeding.

**1c. Gather files in scope:**
- List all source files in scope
- For each, identify its corresponding test file (if any) using the resolved mapping
- Flag source files with no test file at all — these are immediate 🔥 candidates

**1d. Handle zero-test scenarios:**
If no test files exist for the scope:
- Widen the search to the entire project to find *any* test files and extract conventions from those
- If the project has no tests at all, detect conventions from project config (framework, assertion library) and state assumptions explicitly in the report
- Note "No existing tests found — conventions inferred from project config" in the Phase 3 report

---

### Phase 2 — Behaviour Extraction

For each file/module in scope, infer the **behavioural contract** directly from the code:

**What to look for:**
- Every conditional branch (if/else, switch/match, ternary, guard clauses, pattern matching)
- Every method/function's implicit assumptions about its inputs (null/nil/undefined checks, collection access, first/single element access)
- Every error path (thrown exceptions, returned errors, error results, panics, rejected promises)
- Every boundary condition implied by the logic (zero values, empty collections, max values, state transitions)
- Every side effect (database writes, message publishing, file I/O, external API calls, cache mutations)
- Every integration point (service calls, repository calls, message broker interactions, HTTP clients)

**Output format for this phase:**
```
MODULE: path/to/SomeHandler
━━━━━━━━━━━━━━━━━━━━━━━━━━━
Behaviours inferred:
  [B1] Happy path: valid input → expected output with correct state changes
  [B2] Error path: invalid state → appropriate error response
  [B3] Side effect: event/message published with correct payload
  [B4] Integration: downstream service called with correct arguments
  [B5] Boundary: edge case handling for empty/null/zero inputs
```

Store the behaviour list — it will be reused by Phase 7 (no re-extraction needed for the same files).

---

### Phase 3 — Gap Analysis

Map existing tests against extracted behaviours. Classify each behaviour:

| Status | Meaning |
|--------|---------|
| ✅ **Verified** | Test exists AND makes meaningful assertions |
| ⚠️ **Run-only** | Test exists but assertions don't catch mutations here |
| ❌ **Missing** | No test covers this behaviour at all |
| 🔥 **Critical gap** | Missing AND high-risk (frequent change, complex logic, or failure has high impact) |

**Semantic coverage percentage formula:**
```
semantic_coverage = (verified_count + (run_only_count × 0.25)) / total_behaviours × 100
```
- ✅ Verified = 1.0 (full credit)
- ⚠️ Run-only = 0.25 (partial credit — the code runs but assertions are weak)
- ❌ Missing = 0 (no credit)
- 🔥 Critical gap = 0 (no credit, same as missing)

Produce a **Semantic Coverage Report**:

```
SEMANTIC COVERAGE REPORT
━━━━━━━━━━━━━━━━━━━━━━━━
Module: <module name> — <component>
Semantic coverage: <percentage>% (N verified, M run-only, P missing out of T behaviours)

Behaviours:
  ✅ [B1] Happy path — <description>
  ✅ [B2] Error path — <description>
  ❌ [B3] Side effect not verified                    ← GAP (<why it matters>)
  🔥 [B4] Critical integration point untested         ← CRITICAL GAP (<risk>)

Confidence score: <BAND>
```

**This is the primary deliverable.** Always produce this report and present it to the user before generating any tests.

#### Phase 3b — HTTP Response-Shape Audit (default ON, skip with `--no-response-shape`)

If the scope contains any integration tests (files under `test/**/Integration/**` or matching `*IntegrationTests.cs` / `*ApiTests.cs`), spawn the `http-response-test-audit` agent via the Agent tool. Pass `SCOPE` matching the current test-sonar scope (`diff` for `--diff` / default; `all` for non-diff invocations; the explicit path for focused invocations).

The agent groups integration tests by `VERB route-template` and flags endpoints where no test asserts the full response DTO shape. Fold its output into the Semantic Coverage Report as a new section **"Weak response assertions"**, sitting alongside ❌ Missing. Each endpoint-level violation is treated as a ⚠️ Run-only behaviour for confidence-score purposes (the endpoint *is* tested — the assertion just doesn't catch shape drift).

Skip Phase 3b silently if:
- `--no-response-shape` was passed, OR
- The scope contains zero integration test files, OR
- The project isn't .NET (the agent's heuristics are tuned for `HttpResponseMessage` + FluentAssertions).

**Interactive checkpoint:** After presenting the Phase 3 report, ask the user which gaps they want tests generated for. Offer these options:
- "All gaps" — generate tests for every ❌ and 🔥 (default if user says "go ahead" or similar)
- Specific behaviour IDs — e.g., "just B3 and B4"
- "Critical only" — generate tests for 🔥 gaps only

If the scope is small (5 or fewer gaps), skip the checkpoint and generate all tests. The checkpoint exists to avoid wasted work on large scopes, not to slow down small ones.

---

### Phase 4 — Test Generation

Generate tests for the gaps selected by the user (or all gaps if scope is small enough to skip the checkpoint).

**Generation order:** Always generate in priority order: 🔥 first, then ❌. Within each priority level, order by risk (side effects and integration points before pure logic). This ensures the most critical gaps are addressed first, even if the agent hits context limits or the user stops early.

Separate the work into two tiers:

**Tier 1 — Foundation tests** (for 🔥 gaps where no test exists at all):
These verify the basic behavioural contract — correct output for valid input, correct error for invalid input. They are not adversarial; they establish the baseline that must exist before adversarial testing adds value.

**Tier 2 — Adversarial tests** (for all ❌ and 🔥 gaps, after Tier 1):
Written to *break* the code, not to document what already works:
- Use boundary values, not representative ones (0, -1, max int, empty string, null/nil/undefined, empty identifiers)
- Trigger invalid state transitions (e.g., cancel an already cancelled item, decrement from zero)
- Simulate the conditions that trigger the gap (empty collection, missing entity, expired state)
- Assert on *what should NOT happen* as well as what should

**Test generation rules:**
- **Match the project's existing test conventions exactly** — use the framework, assertion library, mocking library, naming conventions, file structure, and patterns detected in Phase 1
- Read at least 2-3 existing test files before generating any new tests to absorb the project's style
- **Test naming:** Use the naming convention already present in the project's existing tests (detected in Phase 1). If the detected convention differs from best practice, or if no clear convention is apparent, highlight this to the user and suggest these recommended patterns — letting them choose before generating tests:
  - **Unit tests:** `MethodName_Scenario_ExpectedBehavior` (e.g., `HandleAsync_WithExpiredListing_ThrowsDomainException`) — maps directly to Phase 2 behaviour extraction
  - **Acceptance/Integration tests:** `Given_Precondition_When_Action_Then_ExpectedOutcome` (e.g., `Given_ValidListing_When_PostToListings_Then_Returns201Created`) — reads as a system-level specification from the consumer's perspective
- If no existing tests were found (Phase 1d), state the inferred conventions explicitly in a comment at the top of the first generated file
- Generate complete, runnable test code — not pseudocode or templates
- Each test should include a comment explaining the gap it addresses and why it matters
- One gap = one focused test class/describe block — don't bundle unrelated gaps

**Verification step:**
Only attempt verification if `build_clean = true` (from Phase 1a). In that case, attempt to build/compile the generated tests (do not run the full suite). If compilation fails, fix the errors before presenting the output. Otherwise, note "Generated tests were not build-verified (project did not build cleanly before analysis, or build command unknown) — run manually" in the output.

---

### Phase 5 — Mutation Validation (only with `--mutation` flag)

Identify **false coverage** — tests that run code but wouldn't catch mutations.

**Flag false coverage when:**
- A test calls a function with no assertion on the return value
- Assertions only check that "no exception was thrown" for logic that should produce specific output
- Tests mock/stub everything and assert only on call counts, not argument values
- Wildcard matchers (e.g., `any()`, `Arg.Any<T>()`, `mock.ANY`) are used where specific matchers would catch regressions

```
FALSE COVERAGE DETECTED
━━━━━━━━━━━━━━━━━━━━━━━
test: <test name> (<file>:<line>)
Problem: <what the assertion misses>
Fix: <specific improvement>
```

---

### Phase 6 — Test Rot Detection (only with `--rot` flag)

Identify tests that have **drifted** from the real code through refactoring:

- Tests that mock/stub a type which has since been refactored or renamed
- Tests that assert on hardcoded values that no longer reflect the real schema or domain rules
- Tests that verify an old function signature or return type
- Tests with tautological assertions (e.g., `assertTrue(true)`, `expect(true).toBe(true)`)
- Tests whose setup builds objects with properties/fields that no longer exist

```
TEST ROT DETECTED
━━━━━━━━━━━━━━━━━
test: <test name> (<file>:<line>)
Problem: <what has drifted and why the test still passes despite being wrong>
Action: <specific fix>
```

---

### Phase 7 — Pre-Release Interrogation (only with `--diff` flag or default no-argument mode)

Focus analysis on changed code vs main branch only. Reuse the behaviour list from Phase 2 — do NOT re-extract behaviours for files already analysed. Only extract new behaviours for files that appear in the diff but were outside the original scope (this should be rare since diff mode is the default scope).

For each changed function/module:
1. Use the behaviours already extracted in Phase 2
2. Check which new behaviours have no test coverage
3. Flag behaviours that were previously tested but whose contract has changed

**Graduated verdict:** The verdict scales with findings severity:

```
PRE-RELEASE INTERROGATION
━━━━━━━━━━━━━━━━━━━━━━━━━
Branch: <branch name>
Diff: <N> files, <M> changed lines

New behaviours introduced (unverified):
  🔥 <handler/function> — no test file exists at all
  ❌ <method> — logic added but no test

Contracts changed (tests now stale):
  ⚠️ <method> — <what changed>
     Existing test still uses old assumption. Test passes but doesn't verify new guard.

Verdict: <one of the following>
```

**Verdict rules:**
- Has 🔥 items → `DO NOT SHIP without addressing critical gaps (🔥 items).`
- Has ❌ but no 🔥 → `SHIP WITH CAUTION — missing coverage (❌ items) increases regression risk. Address before next release.`
- Has only ⚠️ → `LOW RISK — stale tests detected but no missing coverage. Update tests to maintain confidence.`
- No findings → `CLEAR — all new behaviours are covered. Ship with confidence.`

---

## Confidence Score System

Assign a module-level confidence score. The formula adapts based on which phases were run:

**Base formula (always applied):**

| Factor | Weight |
|--------|--------|
| % of behaviours with verified tests | 50% |
| Presence of adversarial/edge-case tests | 30% |
| Run-only test ratio (⚠️ items from Phase 3) | 20% |

**Adjusted formula (when optional phases are included):**

| Factor | Base | With `--mutation` | With `--rot` | With both |
|--------|------|-------------------|--------------|-----------|
| Verified behaviours | 50% | 40% | 45% | 40% |
| Adversarial tests | 30% | 25% | 25% | 20% |
| Run-only ratio | 20% | 15% | 15% | 10% |
| False coverage (Phase 5) | — | 20% | — | 15% |
| Test rot (Phase 6) | — | — | 15% | 15% |

**Score bands:**
- **HIGH** (80-100) — Safe to ship. Critical paths well-covered.
- **MODERATE** (55-79) — Ship with caution. Known gaps exist.
- **LOW** (30-54) — Address critical gaps before shipping.
- **CRITICAL** (0-29) — Do not ship. Fundamental behaviours untested.

---

## Final Output

Every invocation MUST end with:

1. **Semantic Coverage Report** (Phase 3) — the primary deliverable, always included
2. **Generated test code** (Phase 4) — for selected gaps, complete runnable test files
3. **Confidence score** — module-level, with the score band and which formula was used

Optional sections (only if flagged):
- HTTP response-shape audit (Phase 3b, default ON unless `--no-response-shape`)
- False coverage findings (Phase 5, `--mutation`)
- Test rot findings (Phase 6, `--rot`)
- Pre-release interrogation (Phase 7, `--diff` or default)

---

## Output Principles

- **Never generate tests that mirror existing happy paths** — if it's already tested, skip it
- **Always explain WHY a gap is dangerous**, not just that it exists
- **Prioritise by risk**, not by file order or alphabetical logic
- **Match the project's test style exactly** — detect conventions from existing tests, don't assume a framework
- **Generate complete, runnable test code** — not pseudocode or templates
- **One gap = one focused test class/describe block** — don't bundle unrelated gaps into one file
