# CLAUDE.md

## Commands

```bash
dotnet build --configuration Release -p:NetCoreBuild=true
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

- **Commands**: Extend `BaseServiceRequestHandlerAsync<T>`, validate w/ FluentValidation
- **Queries**: Extend `QueryHandlerAsync<TQuery, TResult>`, use Cosmos for GET by ID
- **Permissions**: `[LoadPermissions]` + `command.Permissions.HasPermission()` — every command handler MUST check permissions before performing operations. Never skip this check.
- **Feature folders**: `{Feature}.Endpoint.cs`, `{Feature}.Handler.cs`, `{Feature}.Validator.cs`

### Domain Events vs Brighter Events

| | Domain Events | Brighter Events |
|--|---------------|-----------------|
| Base | `DomainEvent` | `StorableEvent` |
| Handler | `DomainEventHandler<T>` | `BaseServiceRequestHandlerAsync<T>` |
| Mapper | **NO** | **Required** (`MessageMapper<T>`) |
| Markers | None | `IAmPublished`, `IAmSubscribedTo` |
| Location | `Domain/` | `Application/Features/` |

Domain events: `aggregate.Events.Enqueue(new MyDomainEvent(...))` → handler can call `commandProcessor.DepositPostAsync()` to publish Brighter event.

Domain event handlers are auto-discovered by reflection — no manual registration needed.

### Result Types

**CommandResult<T>** - set `command.Result`:

| Type | HTTP |
|------|------|
| `new Success<T>(response)` | 200/204 |
| `response.ToCreated()` | 201 |
| `new Accepted(link)` | 202 |
| `new Forbidden()` | 403 |
| `new NotFound { Message }` | 404 |
| `new Conflict("msg")` | 409 |
| `validation.ToError()` | 422 |
| `new Error(title, ErrorType.General, msg)` | 500 |

**QueryResult<T>** - return directly:

| Type | HTTP |
|------|------|
| `new Success<T>(response)` | 200 |
| `new Forbidden()` | 403 |
| `new NotFound { Message }` | 404 |

**QueryResult<T> pitfall:** Does NOT support C# pattern matching (`is Success<T>`). Use `.IsSuccess` / `.AsSuccess.Content!`. Namespace is `Freemarket.Application`, not `Freemarket.Application.Darker`.

**Endpoints**: Inject `CommandResultHandler`/`QueryResultHandler`, call `resultHandler.Handle(result, endpoint, routeValues)`.

### HATEOAS Gotchas

- Route values must match route parameter names — use `{ id = ... }` not `{ legalEntityId = ... }` when route is `{id:guid}`
- Route values must be strings (`.ToString()`), not raw Guids

### MaybeAggregate Pattern

Use `MaybeGetById` + `Match` for safe aggregate retrieval in queries:

```csharp
var aggregate = await repository.MaybeGetById<Domain.MyAggregate>($"{query.Id}");

return aggregate.Match<QueryResult<MyResponse>>(
    agg => new Success<MyResponse>(new(agg.Id, agg.Name)),
    _ => new NotFound { Message = $"MyAggregate {query.Id} not found" }
);
```

For non-query scenarios where missing = exception, use `Switch`:

```csharp
result.Switch(
    entity => { /* happy path */ },
    _ => throw new InvalidOperationException($"Entity {id} not found")
);
```

### Domain Value Object Pattern

Use `record` (record class) with a private constructor and a `Create` factory method that returns `OneOf<T, Error<string>>`:

```csharp
// Percentage.cs
public record Percentage
{
    public decimal Value { get; }

    [JsonConstructor]
    private Percentage(decimal value) => Value = value;

    public static OneOf<Percentage, Error<string>> Create(decimal value)
    {
        if (value < 0)
            return new Error<string>(Errors.TooLow);

        if (value > 1)
            return new Error<string>(Errors.TooHigh);

        return new Percentage(value);
    }

    public static implicit operator decimal(Percentage percentage) => percentage.Value;

    public static class Errors
    {
        public const string TooLow = "Cannot be below 0%";
        public const string TooHigh = "Cannot be above 100%";
    }
}
```

Key rules:
- **`record`** (record class) -- reference type, value equality, immutable, compiler enforces null safety
- **Private constructor** -- forces creation through `Create`, `[JsonConstructor]` allows deserialization
- **`OneOf<T, Error<string>>` return** -- no exceptions for invalid input, callers use `.Match()` to handle both cases
- **`Errors` static class** -- string constants for error messages, allows callers to match on specific errors
- **Implicit operator** -- optional, for convenient unwrapping to the underlying type
- **Why not `readonly record struct`?** -- structs always have a default value, so `default(T)` or `new T()` creates an instance with zeroed/null fields that bypasses the `Create` factory and silently passes nullable checks
- **Serialization pitfall** -- after renaming/adding properties on aggregates or DTOs, verify `[JsonPropertyName]` matches. Cosmos reads silently return `default` for mismatched property names.

### Avoiding Double Cosmos Reads

When a validator needs the same entity the handler fetches, pass it via `RootContextData` to avoid reading Cosmos twice:

```csharp
// In handler — fetch once, share with validator
var entity = await repository.MaybeGetById<MyAggregate>($"{command.Request.Id}");
command.RootContextData["entity"] = entity;

// In validator — read from context
RuleFor(x => x.Id).CustomAsync(async (id, context, ct) =>
{
    var entity = context.RootContextData["entity"] as MyAggregate;
    // validate against entity...
});
```

## SQL

- **Views**: Name like tables (no `vw_` prefix)
- **Parameterize all queries** — always use `@param` syntax with Dapper. Never concatenate user input into SQL strings.
- **LIKE wildcard escaping**: `.Replace("[", "[[]").Replace("%", "[%]").Replace("_", "[_]")` for search handlers

### SQL Migration Conventions

- `IF NOT EXISTS` guard for CREATE TABLE
- `IF EXISTS/DROP VIEW` then `CREATE VIEW` for views (idempotent)
- Index naming: `UQ_` for unique, `IX_` for non-clustered
- Standard columns: `IsDeleted BIT NOT NULL DEFAULT 0`, `CreatedOn DATETIME2 NOT NULL`, `LastModifiedOn DATETIME2 NOT NULL`
- GRANT permissions on new tables/views to: `FmfxDeveloper`, `FmfxSupportTeam`, `FmfxReleaseAPP`, + module-specific roles
- DbUp scripts are embedded resources — just add `.sql` file to the Scripts folder

## JSON Files

After modifying any `.json` file, validate it is still valid JSON. Common mistakes: trailing commas, missing commas, unquoted keys.

## Code Style

- `Serilog.ILogger` over `Microsoft.Extensions.Logging.ILogger`
- Never log PII, tokens, passwords, or account numbers — use structured logging with safe property names
- File-scoped namespaces, primary constructors, records for DTOs
- Target-typed `new()`: `MyClass x = new();` not `var x = new MyClass();`
- Don't suffix async methods with `Async` (e.g. `GetById` not `GetByIdAsync`)
- **HateoasResource**: Use primary constructors, reference the same route constant as the corresponding endpoint

### NEVER Do

- Disable `<Nullable>enable</Nullable>` or `<TreatWarningsAsErrors>true</TreatWarningsAsErrors>`
- Add `#nullable disable` or `<NoWarn>` for nullable warnings
- Use NUnit - use xUnit (`[Fact]`, `[Theory]`)
- Use `Freemarket.Bdd` - use `Freemarket.Testing.Bdd`
- Use mocking libraries - write hand-rolled fakes/spies
- Use test doubles for our own code - if you can `new` it, test the real thing
- Use StubRepositories for SQL - use real SQL via TestContainers
- Stub `IRepository` - use real Cosmos via TestContainers (`CosmosFixture`)
- Suffix async methods with `Async`
- Add `InternalServerError<ProblemDetails>` to endpoint signatures
- Wrap handler logic in try/catch — let exceptions propagate to the middleware pipeline
- Create abstractions for a single implementation — no premature interfaces
- Add XML doc comments or `// TODO` comments unless linked to a Jira ticket
- Commit commented-out code
- Introduce new aggregates, domain events, or domain rules not defined in the ticket/PRD
- Refactor or reformat code outside the scope of the current ticket
- Use `.GetAwaiter().GetResult()` — use `await`
- Use `dynamic` types
- Catch generic `Exception` without re-throwing or logging

## Testing

Cover as much functionality in unit tests as possible, especially for domain logic. Use integration tests for end-to-end scenarios and endpoint validation.
Every new endpoint must have at least one happy-path integration test and a 401 unauthorized test. Test other error responses (404, 422, 403) in Developer/Unit tests via `CommandResult`, not integration tests.

BDD pattern with `Freemarket.Testing.Bdd.Specification`. Use `/bdd-test` or `/integration-test` skills to scaffold.

Test naming: `[MethodName]_[Scenario]_[ExpectedBehavior]`

Use `FluentAssertions` with `Should().BeEquivalentTo()`.

### Test Doubles

Use `SpyCommandProcessor` from `Freemarket.Testing.TestDoubles` — don't hand-roll a new one:
- `.WasCommandSent<T>()` — verify `SendAsync` was called
- `.PostedToOutbox` — list of events deposited via `DepositPostAsync`
- `.GetSentCommand<T>()` — retrieve a specific sent command

Permission setup in tests: `command.Permissions.AddPermission("key", null!, null!)`

### BDD Sync/Async Overloads

The BDD framework has separate overloads for sync and async steps. Must match:
- Sync: `Given(Action)`, `And(Action)`, `Then(Action)`
- Async: `await GivenAsync(Func<Task>)`, `await AndAsync(Func<Task>)`, `await ThenAsync(Func<Task>)`

If you change a step from `async Task` to `void`, update all call sites from `await AndAsync(method)` to `And(method)`.

### Test Gotchas

- `using Paramore.Brighter;` is required in test files for the `Id` type — it's not in implicit usings
- Test cleanup: call `fixture.ResetDb()` / `ResetRepository` in `DisposeAsync` for each entity type used
- When deleting source files, delete associated test files in the same change or the build breaks

## Commits

```
type(FMFX-12345): Subject

- Details
```

Types: `feat`, `fix`, `chore`, `refactor`, `test`, `docs`

## Pull Requests

- Always run `/risk` to assess and attach a risk category before creating a PR
