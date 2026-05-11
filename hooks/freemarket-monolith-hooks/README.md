# freemarket-monolith-hooks

A bundle of `PreToolUse` and `PostToolUse` hooks that enforce Freemarket
modular-monolith conventions and personal-workflow guardrails the moment Claude
tries to write banned code or run a risky command. Every hook **fails open** on
unrelated files, so installing this plugin in a microservice repo is a no-op:
the hooks self-scope by file glob (`*.Command.cs`, `*.Specs.cs`,
`Migrations/Scripts/*.sql`, etc.) or by command shape (`git commit`,
`gh pr review`).

## What's in here

### Codebase-invariant hooks (Write/Edit gates)

| Hook | Triggers on | Catches |
|---|---|---|
| `enforce-bdd-when-step.sh` | `*.Specs.cs` | `[Fact]` / `[Theory]` test methods that call `Then(...)` without a preceding `When(...)`. The When step is mandatory in Freemarket's BDD pattern, not implicit inside `Then`. |
| `enforce-no-callerUserId-property.sh` | `*.Command.cs` | `CallerUserId` properties or constructor parameters. Duplicates `AuthorizationId` from `InternalCommand<T>` (PlatformCode); the two names drift apart and tests can mask it. |
| `enforce-no-dynamic-in-tests.sh` | `test/**/*.cs` | The `dynamic` keyword. Defeats type safety in projection rows, hides column-rename bugs. |
| `enforce-no-empty-self-link.sh` | `*.cs` | `new HateoasLink("self", string.Empty)` / `""`. Yields a 201 with no Location header and bypasses `ToCreated()` validation. |
| `enforce-no-utcnow-in-readmodel.sh` | `*.Query.cs`, `*ReadModel*Handler.cs` | `DateTimeOffset.UtcNow` / `DateTime.UtcNow`. SQL clock (`GETUTCDATE()`) is the source of truth for read-side time computations; app-clock skew becomes an observable bug. |
| `enforce-permission-before-notfound.sh` | `*.Command.cs` | Handlers that return `NotFound` before checking `HasPermission`. Leaks resource existence to anonymous probes. |
| `enforce-sql-migration-rules.sh` | `*/Migrations/Scripts/*.sql` | New `CREATE TABLE` statements missing GRANTs to the standard roles (FmfxDeveloper / FmfxSupportTeam / FmfxReleaseAPP / module roles) or missing `IsDeleted BIT NOT NULL DEFAULT 0`. |
| `enforce-prd-research.sh` | `tasks/prd-*.md`, `docs/adr/*.md` | "TBD", "Defer to reviewer", "confirm with X" markers in PRDs/ADRs without proof of codebase research. |

### Workflow / process hooks

| Hook | Matcher | Catches |
|---|---|---|
| `enforce-askuserquestion-rules.sh` | `PreToolUse:AskUserQuestion` | Question batches whose answers are already determined by CLAUDE.md, the ticket, or the model's own `(Recommended)` tag. Forces revision before send. |
| `enforce-no-tasks-current-commits.sh` | `PreToolUse:Bash` | `gh pr create` when the branch's commits (vs base) include files under `tasks/current/`. Lets ralph commit prd.json / progress.txt iteratively; only blocks at PR-open. Use `/post-ralph` to archive first. |
| `enforce-pr-build-doctor.sh` | `PostToolUse:Bash` | After `git push` / `gh pr create` on a branch with an open PR, forces `/pr-build-doctor` invocation before further action. |
| `block-pr-approve.sh` | `PreToolUse:Bash` | `event: APPROVE` reviews and `gh pr review --approve`. Approval is the user's call, not the model's. |

## How they fail

All hooks fail open if input parsing breaks. They use `set -e` and `python` for
JSON extraction; if Python is missing or the input shape is unexpected, the
hook exits 0 silently rather than wedging the tool call.

When a violation IS detected, they exit 2 with a stderr message explaining the
rule, the canonical fix, and (for codebase-invariant hooks) a precedent file
showing the right pattern. Per the Claude Code hook contract, exit 2 from
`PreToolUse` denies the tool call and feeds stderr back to Claude.

## Adding a new hook

1. Drop the `enforce-*.sh` script in this folder.
2. Register it in `../hooks.json` under the appropriate matcher.
3. Add a row above.
4. Bump the plugin version per the root `CLAUDE.md`.

Keep hooks self-scoping (file glob or command shape check first, work second)
so installing them in a non-monolith repo costs nothing.
