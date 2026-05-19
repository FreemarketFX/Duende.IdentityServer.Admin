# Ralph Agent Instructions

You are an autonomous coding agent. You implement **exactly ONE user story** per session, then stop.

> **First action every session:** Run these two commands as your FIRST tool calls:
> 1. `REPO_ROOT="$(git rev-parse --show-toplevel)"` — use `$REPO_ROOT` for ALL paths after this
> 2. `cat "$REPO_ROOT/tasks/current/progress.txt"` — see what's already done
>
> Do NOT try to Read any files before running step 1. Do NOT guess paths — the working directory is the repo root but you MUST use `$REPO_ROOT` for all subsequent paths. Do NOT resolve paths against `/c/dev/freemarket/` or any parent of the repo root.

## Hard Rules

1. **ONE STORY PER SESSION.** After committing a completed story, do NOT pick up another story. End your session immediately.
2. **Never commit broken code.** All commits must pass typecheck, lint, and tests.
3. **Never commit line-ending noise.** `git diff` must show only the lines you actually changed.
4. **Never use `git add <specific-files>`.** Always use `git add -A` from `$REPO_ROOT` — never from `/tmp/build` or any other build mirror. The mirror has no `.git` directory; running git there is undefined behaviour.
5. **Always Read a file before Editing it.** The Edit tool requires a prior Read in the same session.
6. **Commit early.** After a successful build, commit WIP before running the full test suite. You can amend later. This prevents total work loss if the iteration is killed.
7. **Prefer direct tool calls over sub-agents.** Use Read/Glob/Grep directly for file discovery and pattern lookups. Do not spawn sub-agents for simple reads — they add 30s+ overhead per invocation.
8. **Use Glob/Grep tools, not `find`/`grep` via Bash.** The built-in tools are faster and have structured output.
9. **Never use `git -C` or `git -c` flags.**
10. **NEVER run build or test commands in the background.** Using `run_in_background` for `dotnet build` or `dotnet test` causes 30+ minute stalls with no ability to cancel or inspect output. Always run foreground with `timeout`. This is the #1 cause of wasted iterations.
11. **Always rebuild after editing source files.** Never use `--no-build` unless you are certain the current build includes all your changes. Stale builds cause phantom test failures.
12. **Scope all searches to `$REPO_ROOT`.** Never Glob/Grep/find parent directories like `/c/dev/freemarket`. The only exception is `../PlatformCode` which may need to be searched for `Freemarket.*` package source.
13. **Batch all Edits before each build.** Plan the full set of source changes for the story, make every Edit, then rsync+build once. Do NOT loop think→edit→build→think→edit→build — assistant-turn latency between small edits dominates iteration time. One build per coherent set of changes.
14. **Don't probe framework-derived classes at runtime.** If you find yourself writing a reflection program, `ShouldSerialize` probe, or diagnostic test to inspect base classes from `Freemarket.*` packages (e.g. `Aggregate<T>`, `SequencedAggregate`), STOP. Read the package source via Glob/Grep on `../PlatformCode` instead. Probe loops on framework internals are the #1 way to burn an iteration with zero progress.
15. **Three-strikes rule.** If three consecutive sub-agent tasks fail on the same surface area (same class, same test, same package), STOP. Append a `BLOCKED:` note to `progress.txt` describing what you tried and why it kept failing, then end the session. Three failures on the same surface almost always indicate missing context (PRD gap, missing repo mount, package unavailable in sandbox) — a fourth attempt will not fix it.

---

## Workflow

**All paths below are relative to the repository root** (i.e. the git toplevel). Use `git rev-parse --show-toplevel` if unsure. Do NOT prepend `scripts/ralph/` or any other prefix to these paths.

PRD and progress files live in `tasks/current/` (active work) and `tasks/archive/` (completed work).

### Phase 1: Orient

1. Find and read the PRD. Check these locations in order (all relative to repo root):
   - `tasks/current/prd.json`
   - `apps/*/tasks/current/prd.json`
   - `tasks/archive/*/prd.json` (latest modified — may need to copy back to `tasks/current/`)
   Try `Read` directly on each candidate; stop at the first hit. Do **not** `Glob`, `find`, or `ls` to look for it — direct Read is one tool call per candidate, and a missing file errors instantly. Once found, remember this path as `$PRD_DIR` for the rest of the session.
2. Read `$PRD_DIR/progress.txt` — pay close attention to **Codebase Patterns** and **Learnings for future iterations**
3. Ensure you are on the branch specified by `branchName` in the PRD. If not, check it out or create it from `main`
4. **Clean up killed-iteration noise.** Run `git checkout HEAD -- tasks/` to restore any line-ending changes from killed iterations. Do not investigate line endings — just restore.
5. Run `git status`. If there are untracked or uncommitted files (other than ralph artifacts):
   - A previous iteration was likely killed. Try `git stash pop` to recover the work.
   - If `git stash pop` fails (conflicts), run `git stash drop` to discard the killed work, then `git checkout -- .` to clean the tree.
   - Continue to Phase 2 once the working tree is clean.
6. **Discover project layout early.** Before writing any code:
   - Glob `test/**/*.csproj` to find actual test project names — do NOT assume template names like `Module.Tests` from CLAUDE.md
   - Read the solution file (`*.slnx` or `*.sln`) to understand which projects are currently included
   - Remember these paths for the build/test phases

### Exploration Budget

Spend **max 10-15 tool calls** on exploration before writing code. If `progress.txt` has a **Codebase Patterns** section, trust it — only explore patterns not already documented there. Prior iterations documented patterns specifically to prevent redundant exploration. Each iteration re-exploring from scratch is the #1 cause of wasted context.

### Phase 2: Implement

7. Pick the **highest-priority** story where `passes: false`
8. Implement that story
9. Run **all** quality checks — build, full test suite, lint. Verify zero regressions.

### Phase 3: Record & Commit

10. Update nearby `CLAUDE.md` files with any reusable patterns you discovered (see guidelines below)
11. Update `$PRD_DIR/prd.json` — set `passes: true` for the completed story
12. Append to `$PRD_DIR/progress.txt` (see format below)
13. Commit (see commit procedure below)

### Phase 4: Stop

14. **You are done.** Reply with `<promise>COMPLETE</promise>` if every story now has `passes: true`. Otherwise, **end your session silently.** Another iteration will pick up the next story. Do NOT continue to the next story.

---

## Commit Procedure

Extract the Jira ticket number from the branch name (pattern: `FMFX-XXXXX_description`).

Run this exact sequence from the **repository root**:

```bash
cd "$(git rev-parse --show-toplevel)"
git add -A
git status          # verify nothing unstaged/untracked
git diff --cached --stat   # verify only expected files changed
git commit -m "feat(FMFX-XXXXX): concise description"
```

If `git status` still shows unstaged/untracked files after `git add -A`, run it again until the working tree is clean. Do not commit until it is.

Use conventional commit format:

- `feat(FMFX-XXXXX): description` for new functionality
- `fix(FMFX-XXXXX): description` for bug fixes

---

## Build Strategy

Building inside the sandbox uses virtiofs (Docker's host-to-container file sharing). This is fragile and almost always fails with MSB3248 errors. **Always rsync first.**

1. **New projects MUST be in the solution file.** If you created or added new `.csproj` files, they won't build unless they're in `*.slnx` (or `*.sln`). Check with:
   ```bash
   grep 'YourNewProject' *.slnx  # or *.sln
   ```
   If missing, run `dotnet sln add path/to/Project.csproj` **before** building. Building without this wastes 4+ minutes on a build you'll have to redo.
2. **Always copy sources before building:**
   ```bash
   REPO_ROOT="$(git rev-parse --show-toplevel)"
   rsync -a --exclude='.git' --exclude='bin' --exclude='obj' --exclude='.claude/projects' "$REPO_ROOT/" /tmp/build/
   cd /tmp/build && dotnet build --configuration Release /p:NetCoreBuild=true
   ```
3. **Never `cp -r` the entire repo.** This copies `.git`, `bin`, `obj` and causes OOM kills.
4. **After building in `/tmp/build`**, run tests from there too — but commit from the original repo root.
5. **MinVer warnings (MINVER1001) are expected** when building in `/tmp/build` because `.git` is excluded. Ignore them.
6. **Skip rsync if only `tasks/` changed.** If `git diff --name-only` since last build shows only `tasks/**` (PRD/progress) or other non-source files, do NOT rsync — `/tmp/build` is already correct. Rsync of the full repo costs ~1 minute.
7. **On a warm `/tmp/build`, prefer `--no-restore` + project filter.** After a successful full-solution build, subsequent compiles of the same iteration can skip restore: `cd /tmp/build && timeout 300 dotnet build src/YourModule/Application/Application.csproj --configuration Release --no-restore`.
8. **Do NOT rebuild `HostApp` just to re-verify after your project builds clean.** `HostApp` pulls private GitHub Packages (`Freemarket.Persistence.Blob` etc.) that fail with `NU1301` in the sandbox — this is a known auth limitation, not a regression. If your changed project builds, stop.

### StyleCop Pre-Check (before every build)

Before running `dotnet build`, scan every `.cs` file you modified for common violations. Fix auto-fixable ones in-place, report manual-fix ones in progress.txt.

**Identify targets:**
```bash
git diff --name-only main...HEAD -- '*.cs'
```

**Auto-fix these (edit the file directly):**
- **SA1210**: Reorder `using` directives alphabetically (`System.*` first)
- **SA1413**: Add trailing comma to last element in multi-line initializers/enums
- **SA1512**: Remove blank line immediately after a `//` comment
- **SA1513**: Closing brace must be followed by a blank line — and a closing brace must NOT be followed by an extra blank line. After Edits, scan for `}\n\n\n` (extra blank) and `}\n[^\n}]` (missing blank before next member) on modified files.
- **IDE1006**: Private fields must be `_camelCase` (prefix with `_`)

**Check and report only (do NOT auto-reorder):**
- **SA1202**: Public members must appear before private members
- **SA1203**: Constants must appear before non-constant fields
- **SA1214**: Readonly fields must appear before non-readonly fields
- **SA1128**: Constructor initializer (`: base(...)`) must be on its own line
- **SA1502**: Class/method body must not be on a single line (except `=>` members)
- **SA1117**: Parameters split across lines must each be on their own line

If manual-fix violations are found, note them in progress.txt under the current story.

Do NOT skip this step — run it before every `dotnet build`.

### Build & Test Execution Rules

**CRITICAL: Never run build+test as a single compound or background command.** Run each step as a separate foreground Bash call so you can inspect results and react to failures:

```bash
# Step 1: rsync
rsync -a --exclude='.git' --exclude='bin' --exclude='obj' --exclude='.claude/projects' "$REPO_ROOT/" /tmp/build/

# Step 2: build (separate call, foreground, WITH TIMEOUT)
cd /tmp/build && timeout 600 dotnet build --configuration Release /p:NetCoreBuild=true

# Step 3: test (separate call, foreground, with timeout)
cd /tmp/build && timeout 300 dotnet test --configuration Release --no-build
```

- **Never chain rsync, build, and test with `&&` in a single command.** If the build fails you waste the entire test timeout waiting.
- **Never use background tasks (`run_in_background`) for build or test.** Background tasks + `TaskOutput(block:true)` create a deadlock if the command hangs — you cannot intervene, cancel, or inspect partial output.
- **Always use `timeout 600` (10 min) on `dotnet build` and `timeout 300` (5 min) on `dotnet test`.** If a build hasn't finished in 10 minutes or tests in 5 minutes, something is hung. Kill it and investigate rather than waiting for the outer timeout.
- **If a test run times out**, check whether TestContainers is trying to pull a Docker image that isn't available in the sandbox. Skip those tests and note them for CI.

### If a build or test is killed (exit code 143)

Exit 143 = SIGTERM (timeout or outer kill). Do NOT retry the exact same full-solution build. Instead:
1. Check if `/tmp/build` still has the rsync'd sources — if so, skip rsync
2. Build only the changed project first: `cd /tmp/build && timeout 300 dotnet build src/YourModule/Application/Application.csproj --configuration Release`
3. If that passes, attempt the full solution build
4. If the full build keeps timing out, commit what you have (rule 6) and note the issue in progress.txt

### Testing in the sandbox

- **Use discovered test paths.** Use the test project paths you found in Phase 1 step 6. Do NOT hardcode template names like `Module.Tests`.
- **Run all tests by default.** Filter syntax is unreliable in the sandbox — `--filter-class`, `--filter-method`, and `--filter` all fail with some test runners. Prefer running the full suite:
  ```bash
  cd /tmp/build && timeout 300 dotnet test --configuration Release --no-build
  ```
  If you must filter, try `dotnet test --filter "FullyQualifiedName~ClassName"` as a best-effort fallback — but don't spend more than one attempt if it fails.
- **Cosmos emulator does NOT work in the sandbox.** The Docker image is too large to pull reliably through the sandbox network proxy. Skip Cosmos-dependent tests and defer them to CI. Only run SQL-based tests.
- **SQL Server (TestContainers) works** — MCR images for SQL Server pull successfully.
- **Always rsync the full repo, not individual app subdirectories.** Projects have cross-repo NuGet/build dependencies that break with partial copies.
- **Config/test fixture coupling:** When adding config dependencies to a module's `Configuration` class (e.g., `config.GetRequiredSection("Sql")`), always update the corresponding test fixture to provide that config section. Missing config in test fixtures causes `InvalidOperationException` at test time.

---

## Line Ending Discipline

Most repos have `.gitattributes` with `* text=auto`, which means git normalises line endings on commit. Check for this first — if present, you generally don't need to worry about CRLF.

If `.gitattributes` does NOT handle line endings:

- Prefer `sed -i` for targeted edits — it preserves line endings of untouched lines.
- If you rewrite an entire file, pipe through `unix2dos` before saving.
- **Never** use heredocs (`cat << 'EOF'`) or `echo` to write CRLF files — they strip `\r`.

Either way, before committing run `git diff --stat`. If a file shows all lines changed, you broke line endings. Fix with `unix2dos <file>` and re-stage. Only commit when the diff shows **only the lines you intentionally changed.**

---

## Sandbox Limitations

These tools/commands are **not available** in the sandbox:

| Missing | Alternative |
|---------|-------------|
| `file` | `od -c <file> \| head` or check `.gitattributes` |
| `python3` / `pip` | `node -e '...'` or `jq` |
| `curl` / `wget` | Denied by settings — use tool calls instead |

---

## Progress Report Format

**Always append** to `$PRD_DIR/progress.txt` — never overwrite.

```
## [Date + Timestamp] - [Story ID]
- What was implemented
- Files changed
- Context usage: [tokens used]
- **Learnings for future iterations:**
  - Patterns discovered
  - Gotchas encountered
  - Useful context for future agents
---
```

### Codebase Patterns

If you discover a **general, reusable pattern**, add it to the `## Codebase Patterns` section at the top of `$PRD_DIR/progress.txt` (create it if missing). Only add patterns that apply broadly, not story-specific details.

---

## Updating CLAUDE.md Files

Before committing, check whether any directory you edited has a `CLAUDE.md`. If you learned something reusable about that area, add it. Good additions:

- "When modifying X, also update Y"
- "This module uses pattern Z for all API calls"
- "Tests require the dev server on port 3000"

Do not add story-specific details or temporary debugging notes.

---

## Browser Testing

If you have browser testing tools (e.g., via MCP) and your story changes UI:

1. Navigate to the relevant page
2. Verify the changes work
3. Screenshot if useful

If no browser tools are available, note in `$PRD_DIR/progress.txt` that manual browser verification is needed.