# CLAUDE.md

## Commands

```bash
dotnet build --configuration Release /p:NetCoreBuild=true
dotnet run --project ./test/Module.Tests/Module.Tests.csproj --no-build --configuration Release -- --results-directory TestResults --report-trx
dotnet run --project ./test/Module.Tests/Module.Tests.csproj --no-build --configuration Release -- --filter-class "*TestClassName*"
```

## Skills

Use these skills to scaffold code following codebase patterns:

| Skill | Purpose |
|-------|---------|
| `/feature` | Scaffold command endpoint (POST/PUT/DELETE) with handler, validator, DTOs |
| `/query` | Scaffold query endpoint (GET) with handler using MaybeAggregate pattern |
| `/domain-event` | Create domain event + handler in Domain layer |
| `/brighter-event` | Create Brighter event + mapper + handler for cross-service messaging |
| `/integration-test` | Scaffold API integration test (required for new endpoints) |
| `/bdd-test` | Scaffold BDD unit test for domain/developer tests |
| `/risk` | Assess PR risk level before creating PR |
| `/ralph-log-doctor` | Postmortem analysis of a ralph-sandbox.log run; produces a punch list of fixes |

## Agents

Specialised subagents available via the Agent tool. Defined in `.claude/agents/<name>.md`, distributed via `claude-shared/.claude/agents/` (same path as scenario rules).

| Agent | Purpose |
|-------|---------|
| `ralph-log-doctor` | Read-only postmortem analyst for ralph-sandbox runs. Spawned by the `/ralph-log-doctor` skill. |
| `ralph-prd-validator` | Read-only coverage analyst that maps every PRD requirement to a covering user story / AC bullet. Spawned by the `/ralph` skill before commit. |
| `http-response-test-audit` | Read-only auditor of HTTP integration tests. Groups tests by `VERB route-template` and flags endpoints with no full-response-shape assertion. Invoked directly via the Agent tool. |

## Scenario-Specific Rules

Load the relevant rule file when working in that area:

| Rule | When |
|------|------|
| @.claude/rules/endpoints.md | Editing `*.Endpoint.cs`, `*.Handler.cs`, command/query handlers |
| @.claude/rules/openapi.md | Endpoint signatures, request DTOs, `[AsParameters]` records |
| @.claude/rules/domain.md | Working in `src/*/Domain/` (aggregates, value objects, MaybeAggregate) |
| @.claude/rules/events.md | Creating or modifying domain / Brighter events |
| @.claude/rules/change-feed.md | Read-model handlers on the Cosmos change-feed path |
| @.claude/rules/validators.md | Editing `*.Validator.cs` |
| @.claude/rules/sql.md | Editing `*.sql` or code that executes SQL |
| @.claude/rules/testing.md | Anything under `test/` |
| @.claude/rules/infrastructure.md | Bicep / Cosmos containers / `.json` edits |
| @.claude/rules/pull-requests.md | Commits and PR creation |

## Before Writing Code

- **Read before writing** — never modify a file you haven't read. Never assume a pattern; verify it exists in the codebase first.
- **Find existing examples** — before scaffolding any new feature, query, event, or test, find at least one existing example in the codebase and follow its patterns exactly. For `Freemarket.*` packages, read the source in `../PlatformCode`.
- **Check for existing implementations** — search for existing code that already does what you're about to build. Duplicate functionality is a common mistake.
- **Understand the aggregate** — before modifying any aggregate, read the entire aggregate file and its domain events. Understand invariants before changing state.
- **Trace the full path** — for endpoint changes, trace: Endpoint → Handler → Domain → Persistence → Tests. Don't modify one layer without understanding the others.

## Architecture

Modular monolith (.NET 10.0) w/ DDD + CQRS (Paramore Brighter/Darker).

```
src/Module/Application/   # Commands, Queries, Endpoints, Handlers, Validators
src/Module/Domain/        # Aggregates, Domain Events
test/Module.Tests/        # Architecture, Domain, Developer (BDD), Integration
```

### Key Patterns

- **Commands**: extend `BaseServiceRequestHandlerAsync<T>`, validate w/ FluentValidation.
- **Queries**: extend `QueryHandlerAsync<TQuery, TResult>`, use Cosmos for GET by ID.
- **Feature folders**: `{Feature}.Endpoint.cs`, `{Feature}.Handler.cs`, `{Feature}.Validator.cs`.
- **Permissions, Result Types, HATEOAS, MaybeAggregate, Value Objects, Events** — see scenario rules above.

## Code Style

- `Serilog.ILogger` over `Microsoft.Extensions.Logging.ILogger`.
- Never log PII, tokens, passwords, or account numbers — use structured logging with safe property names.
- File-scoped namespaces, primary constructors, records for DTOs.
- **Request DTOs**: init-only properties (`public required T Prop { get; init; }`), not positional parameters — positional params with 2+ attribute types crash .NET 10 OpenAPI generation.
- Target-typed `new()`: `MyClass x = new();` not `var x = new MyClass();`.
- Don't suffix async methods with `Async` (e.g. `GetById` not `GetByIdAsync`).
- Use Transient over Scoped DI registrations.
- Empty type bodies use `{ }` not `;` (SA1106).

## NEVER Do

- Disable `<Nullable>enable</Nullable>` or `<TreatWarningsAsErrors>true</TreatWarningsAsErrors>`.
- Add `#nullable disable` or `<NoWarn>` for nullable warnings.
- Use NUnit — use xUnit (`[Fact]`, `[Theory]`).
- Use `Freemarket.Bdd` — use `Freemarket.Testing.Bdd`.
- Use mocking libraries — write hand-rolled fakes/spies.
- Use test doubles for our own code — if you can `new` it, test the real thing.
- Use StubRepositories for SQL — use real SQL via TestContainers.
- Stub `IRepository` — use real Cosmos via TestContainers (`CosmosFixture`).
- Suffix async methods with `Async`.
- Add `InternalServerError<ProblemDetails>` to endpoint signatures.
- Wrap handler logic in try/catch — let exceptions propagate to the middleware pipeline.
- Create abstractions for a single implementation — no premature interfaces.
- Add XML doc comments or `// TODO` comments unless linked to a Jira ticket.
- Commit commented-out code.
- Introduce new aggregates, domain events, or domain rules not defined in the ticket/PRD.
- Refactor or reformat code outside the scope of the current ticket.
- Remove positional record parameters without grepping for `new TypeName(` — all construction sites break.
- Use `.GetAwaiter().GetResult()` — use `await`.
- Use `dynamic` types.
- Catch generic `Exception` without re-throwing or logging.
- Use `git update-index --assume-unchanged` as a rebase/push workaround — it silently hides files from tracking. Use `git stash` instead.
