# Testing

Applies under `test/`.

## General

- Cover as much functionality in unit tests as possible, especially domain logic. Use integration tests for end-to-end and endpoint validation.
- Every new endpoint must have at least one happy-path integration test and a 401 unauthorized test. Test other error responses (404, 422, 403) in Developer/Unit tests via `CommandResult`, not integration tests.
- BDD pattern with `Freemarket.Testing.Bdd.Specification`. Use `/bdd-test` or `/integration-test` skills to scaffold.
- Naming: `[MethodName]_[Scenario]_[ExpectedBehavior]`.
- Use `FluentAssertions` with `Should().BeEquivalentTo()`.

## Test Doubles

Use `SpyCommandProcessor` from `Freemarket.Testing.TestDoubles` — don't hand-roll a new one:
- `.WasCommandSent<T>()` — verify `SendAsync` was called
- `.PostedToOutbox` — list of events deposited via `DepositPostAsync`
- `.GetSentCommand<T>()` — retrieve a specific sent command

Permission setup: `command.Permissions.AddPermission("key", null!, null!)`.

Never use mocking libraries — write hand-rolled fakes/spies. Never use test doubles for our own code (if you can `new` it, test the real thing). Never use StubRepositories for SQL (use real SQL via TestContainers). Never stub `IRepository` (use real Cosmos via `CosmosFixture`).

## BDD Sync/Async Overloads

Separate overloads for sync vs async — must match:
- Sync: `Given(Action)`, `And(Action)`, `Then(Action)`
- Async: `await GivenAsync(Func<Task>)`, `await AndAsync(Func<Task>)`, `await ThenAsync(Func<Task>)`

Changing a step from `async Task` to `void` requires updating all call sites from `await AndAsync(method)` to `And(method)`.

## Gotchas

- `using Paramore.Brighter;` is required in test files for the `Id` type — not in implicit usings.
- Test cleanup: call `fixture.ResetDb()` / `ResetRepository` in `DisposeAsync` for each entity type used.
- When deleting source files, delete associated test files in the same change or the build breaks.
- 401 unauthorized tests don't need seed data — set invalid auth token and make the request.
- `FluentAssertions` is transitive from `Freemarket.Testing` — no explicit package reference.

## SQL Fixture Cleanup

SQL-backed test fixtures use [Respawn](https://github.com/jbogard/Respawn) for between-test reset — never hand-roll `TRUNCATE` / `DELETE` per table.

- Wrap the shared `MsSqlFixture` (Testcontainers SQL Server) in a module-specific fixture that owns its schema.
- After creating the schema in `InitializeAsync`, call `await _sqlFixture.InitializeRespawnAsync(["MySchema"])`. The Respawn snapshot is taken at that point; only post-snapshot rows are wiped on reset.
- Expose a single `ResetAsync()` on the module fixture that delegates to `_sqlFixture.ResetAsync()`. Call it from each spec's `InitializeAsync` for per-test isolation.
- Defaults inside `MsSqlFixture.InitializeRespawnAsync`: `DbAdapter.SqlServer`, `WithReseed = true`. Opt out of reseed via the second arg (`InitializeRespawnAsync(schemas, withReseed: false)`); for full control, pass a `RespawnerOptions` directly to the second overload.
- Canonical example: `AccountSqlFixture` in `PlatformModularMonolith/test/Platform.Tests/Developer/Account/AccountSqlCollection.cs`.

## Auth-Rejection Integration Tests

401 and 403 integration tests MUST target a known-good resource ID, never a random `Guid`. Posting to `Guid.NewGuid()` lets a 401 race a 404 — the test passes even if auth is broken.

- Seed the resource first, use its real ID.
- 403 follows the same rule: caller must lack the permission while the resource exists.

## Shared Test Infrastructure

If a test helper, fake, spy, factory, or DTO wrapper appears in 2+ test files, extract to `Tests.Shared/` in the **same PR** as the second copy. Don't wait for the third.

Before adding a helper, grep `Tests.Shared/` and sibling test step files. Common offenders: auth + permission setup, DTO deserialization wrappers, spy implementations of common interfaces, factory methods that bypass domain validation via JSON round-trip.

## Integration Test DTOs

Integration tests MUST use the source response DTOs and domain types for deserialization, not locally-defined copies. Only define a test-local wrapper record when asserting on a field the base class doesn't expose (e.g. `Links` from `HateoasResource`). Follow the `sealed record FooResponseWithLinks(...)` pattern.
