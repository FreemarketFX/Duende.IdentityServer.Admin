# Commits & Pull Requests

Applies at commit time and PR creation.

## Commit Format

```
type(FMFX-12345): Subject

- Details
```

Types: `feat`, `fix`, `chore`, `refactor`, `test`, `docs`.

Extract the ticket number (e.g. `FMFX-12345`) from the branch name pattern `FMFX-XXXXX_description`.

## Before Creating a PR

- Run `/risk` to assess and attach a risk category.
- Run `/self-code-review` to catch issues before reviewers see them.

## Diff-Stat Hard Gate (every commit)

After staging, run `git diff --cached --stat` and read the full output into context. Scan every row: if any file shows up that you don't recognise editing this iteration, abort the commit — that's line-ending or whitespace noise, NOT an intentional change. Do NOT try to talk yourself into it. Run `unix2dos <file>` (or `dos2unix` if the rest of the file is LF) on the offending paths, re-stage, re-check. If you can't get the stat down to only files you intentionally edited in 2 attempts, abort the iteration. Noise-laden commits poison `git blame` for every line in the touched files.

## PR Hygiene

- **No unrelated / drive-by changes.** Every file in the diff MUST map to an AC line on the current ticket. Drive-by fixes go in their own PR, or a clearly labelled separate commit with a call-out in the PR description. Before `gh pr create`, run `git diff main..HEAD --name-only` and sanity-check every path.
- **No sandbox / ralph artifacts.** Check for stray dated archive folders, `claude-shared/` subtree edits (which go in their own PR to the claude-shared repo), or test/file renames from another ticket.
- **NEVER commit `tasks/current/`** files (`prd.json`, `progress.txt`). They cause merge conflicts — archive them via `/post-ralph` before creating the PR.
- **Keep response shapes consistent** across related endpoints on the same resource. When changing a DTO, event, or aggregate shape, grep for every `*.Response.cs`, `*Event.cs`, and `Get*.Query.cs` referencing the resource. Align in the same PR, or explicitly note which later PR will align them.
- **Only register endpoint names, permissions, and HATEOAS links for endpoints that exist.** Never forward-declare a constant or emit a link for an endpoint that hasn't been implemented yet.

## Test-Body Rewrites

Rewriting an existing test body is a different action from changing the code under test. Reviewers can spot test additions and deletions easily; replacements are quieter — the file shows up as "modified", git diff shows the new body, but the reviewer has no built-in cue that the *assertion* changed.

If a PR modifies any `[Fact]` or `[Theory]` body (not just adds or removes one), the PR description must list which invariant each rewritten test now covers.

A rewritten body that:

- delegates to another existing test method (`MethodName();`),
- is meaningfully shorter than the original, OR
- no longer aligns with the test name's verb (`EachHas*`, `*Distinct*`, `*Per*`, `*Throws*`, `*Returns*`)

is presumed broken. Either restore the original invariant against the new code shape, or rename / delete the test. A test whose name promises X but body asserts Y (or asserts nothing meaningful) is worse than no test — it presents as coverage in CI and lies in the PR description.

This rule exists because of [FMFX-15607] — a "simplification" PR rewrote `EachHasDistinctContainerOptions` to a single call to an adjacent test, erasing the only assertion that would have caught the underlying multi-instance options bug ([FMFX-16048]). The bug then persisted through three more PRs.
