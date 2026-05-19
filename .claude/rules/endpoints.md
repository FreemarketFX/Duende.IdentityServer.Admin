# Endpoints & Handlers

Applies when editing `*.Endpoint.cs`, `*.Handler.cs`, or any command/query handler.

## Result Types

**CommandResult<T>** — set `command.Result`:

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

**QueryResult<T>** — return directly:

| Type | HTTP |
|------|------|
| `new Success<T>(response)` | 200 |
| `new Forbidden()` | 403 |
| `new NotFound { Message }` | 404 |

**QueryResult<T> pitfall:** does NOT support C# pattern matching (`is Success<T>`). Use `.IsSuccess` / `.AsSuccess.Content!`. Namespace is `Freemarket.Application`, not `Freemarket.Application.Darker`.

## Endpoint Wiring

- Inject `CommandResultHandler` / `QueryResultHandler`, call `resultHandler.Handle(result, endpoint, routeValues)`.
- `Results<>` return type must list ALL possible result types or you get `RuntimeBinderException` at runtime.
- Never add `InternalServerError<ProblemDetails>` to endpoint signatures.
- Never wrap handler logic in try/catch — let exceptions propagate to the middleware pipeline.

## Correlation IDs

Propagate the inbound correlation ID. Never call `Id.Random()` or `new Id(Guid.CreateVersion7().ToString())` when constructing a command or query that takes one.

`HttpRequestContext.CorrelationId` is set from the inbound `X-Correlation-ID` header (or a generated v7 GUID if absent). A fresh ID at the boundary severs the trace between caller, command, outbox event, and downstream consumers — debugging cross-service flows becomes impossible.

**In endpoints** — pass `httpRequestContext.CorrelationId` (inject via `[FromServices]`):

```csharp
// Wrong
new MyCommand(..., Id.Random(), httpRequestContext.AuthorizationId);
new MyCommand(..., new Id(Guid.CreateVersion7().ToString()), ...);

// Right
new MyCommand(..., httpRequestContext.CorrelationId, httpRequestContext.AuthorizationId);
```

**In handlers that emit follow-up commands or events** — propagate the inbound command/event's correlation ID, don't generate a new one:

```csharp
// Wrong
await commandProcessor.SendAsync(new FollowUpCommand(..., Id.Random(), ...), ct);

// Right
await commandProcessor.SendAsync(new FollowUpCommand(..., command.CorrelationId, ...), ct);
```

Same rule applies to queries that take a correlation ID.

## HATEOAS Gotchas

- Route values must match route parameter names — use `{ id = ... }` not `{ legalEntityId = ... }` when route is `{id:guid}`.
- Route values must be strings (`.ToString()`), not raw Guids.
- `HateoasResource`: use primary constructors, reference the same route constant as the corresponding endpoint.

## Permissions

`[LoadPermissions]` + `command.Permissions.HasPermission()` — every command handler MUST check permissions before performing operations. Never skip.

## Pipeline Integrity — `base.HandleAsync` Called Exactly Once

Every `HandleAsync` override on a Brighter handler MUST call `base.HandleAsync` **exactly once**, as the final statement of the method.

`base.HandleAsync` runs the rest of the Brighter pipeline — retry policies, log enrichers, metrics, module-level decorators (e.g. `[ExchangesLogContextEnricherAsync]`). Skipping it from any branch silently bypasses those steps. The single-bottom-call invariant eliminates that bug class structurally.

### Canonical shape

Extract the handler body into a local function (or private method for handlers over ~50 lines) returning `CommandResult<TResponse>`. Implicit conversions on `CommandResult<T>` let each early return read naturally as `return new Forbidden();`, `return new NotFound { Message = "..." };`, etc.

```csharp
public override async Task<TCommand> HandleAsync(TCommand command, CancellationToken ct = default)
{
    command.Result = await ProcessAsync();
    return await base.HandleAsync(command, ct);

    async Task<CommandResult<TResponse>> ProcessAsync()
    {
        if (!command.Permissions.HasPermission(...)) return new Forbidden();
        var entity = await repository.GetById(...);
        if (entity is null) return new NotFound { Message = "..." };
        // ... happy path ...
        return new Success<TResponse>(response);
    }
}
```

### What this replaces

- `command.Result = X; return await base.HandleAsync(command, ct);` repeated through bool guards — early returns belong in `ProcessAsync`, returning `CommandResult<TResponse>`.
- Threading `return await base.HandleAsync(...)` through every `.Match` / `.Switch` arm — set `command.Result` in arms (or have `ProcessAsync` return the result), and `base.HandleAsync` runs once at the bottom.

## Handler Shape — Don't Over-Extract `.Match` / `.Switch` Arms

The OneOf rule (see `domain.md`) requires `.Match` / `.Switch` for branching. In command handlers this can balloon into a tree of trivial private helpers. Keep the flow flat by inlining lambdas that don't earn a name.

### Extract a helper only when

- The branch has **>1 caller**, OR
- The branch does **substantive work** (repo calls, further branching, non-trivial logic).

A 1–3 line lambda (e.g. log + set `command.Result`) is not substantive. Use a block lambda inline.

### Anti-patterns — inline these instead

1. **Set-result-and-return helpers.** A helper whose entire body is `command.Result = X; return await base.HandleAsync(command, ct);` should be the negative arm of a `.Match` / `.Switch`, not its own method.
2. **Guard-then-delegate helpers.** A helper that does a single `if` check then tail-calls another helper should be inlined: put the guard in the calling `.Match` arm, fall through to the real helper.

### Recursive

The same rule applies at every nesting level — a deep arm's own `.Match` / `.Switch` should also inline pure result-setters and guard-then-delegate fragments.

### Example — before

```csharp
return await (await repository.MaybeGetById<Beneficiary>(id)).Match(
    b => HandleWithBeneficiary(b, command, ct),
    _ => SetBeneficiaryNotFound(command, ct));

private async Task<TCommand> SetBeneficiaryNotFound(TCommand command, CancellationToken ct)
{
    command.Result = new NotFound { Message = $"Beneficiary {command.BeneficiaryId} not found" };
    return await base.HandleAsync(command, ct);
}
```

### Example — after

```csharp
await (await repository.MaybeGetById<Beneficiary>(id)).Switch(
    b => await HandleWithBeneficiary(b, command, ct),
    _ => command.Result = new NotFound { Message = $"Beneficiary {command.BeneficiaryId} not found" });

return await base.HandleAsync(command, ct);
```

`HandleWithBeneficiary` mutates `command.Result` itself (it's not pure-passthrough — it does substantive work). The negative arm assigns inline. `base.HandleAsync` is called once at the bottom of the top-level method, not threaded through every leaf.

## Avoiding Double Cosmos Reads

When a validator needs the same entity the handler fetches, pass it via `RootContextData`:

```csharp
// Handler — fetch once, share
var entity = await repository.MaybeGetById<MyAggregate>($"{command.Request.Id}");
command.RootContextData["entity"] = entity;

// Validator — read from context
RuleFor(x => x.Id).CustomAsync(async (id, context, ct) =>
{
    var entity = context.RootContextData["entity"] as MyAggregate;
});
```
