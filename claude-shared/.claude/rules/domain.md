# Domain Layer

Applies in `src/*/Domain/`.

## OneOf Return Types

When consuming any `OneOf<T1, T2, ...>` (domain mutations, `MaybeGetById`, validation services, etc.), always use `.Match()` (returns a value) or `.Switch()` (side effects only) and handle every arm explicitly. Never:

- Access `.Value` / `.AsT0` / `.AsT1` / `.AsSuccess()` directly — bypasses exhaustiveness; a new union arm silently compiles, and any current failure is silently dropped.
- Use `.IsT0` / `.IsT1` if/else branches — same problem; compiler won't catch missed cases.
- Cast or pattern-match (`is Success`) — defeats the type system OneOf is enforcing.
- Use `.Match<T?>(s => s, _ => null)` (or any silent-to-null shape) to swallow the failure arm without handling it. If swallowing genuinely is the right behaviour (e.g. the failure means "doesn't apply, skip"), use `.Switch` and add an inline comment explaining why the failure is intentionally discarded.

`.Match` for queries / value-producing flows; `.Switch` for command handlers that mutate state or set `command.Result`.

### Domain mutations: failure arms must carry typed identity

`OneOf<Success, Error<string>>` on a domain mutation is forbidden. `Success` is unit, `Error<string>` is a string with a wrapper — two positional buckets that carry no semantic information for the compiler to enforce. Adding a new failure mode is just another string constant; existing callers silently route every new failure into the same generic-string branch. The shape forces every consumer into `IsT1`/`AsT1` checks or `.Match`-as-fork-extract (one arm yields `null`, the other yields the value), both of which bypass the exhaustiveness OneOf exists to enforce.

Replace with a multi-arm OneOf whose failure arms each carry typed identity:

```csharp
// Instead of separate AddDocument / OverwriteDocument each returning OneOf<Success, Error<string>>:
public OneOf<DocumentAdded, DocumentOverwritten, AlreadyExistsAndNoOverwrite>
    UpsertDocument(string filename, bool overwrite) { ... }
```

Each arm is a distinct outcome the caller branches on. The compiler enforces exhaustiveness on something real. Adding a new failure mode forces a compile error at every call site.

`void`+throw is **not** an acceptable replacement. Throwing makes the failure invisible at the type level, lets callers forget to handle it, and bunches every rejection mode under whatever exception type the global handler catches — usually a 500. Keep the failure on the return type; force the caller to acknowledge it.

### Don't use `.Match` as a fork-extract

If your `.Match` produces a nullable (one arm returns `null`, the other returns the value) just so the caller can `if (x is not null) ...` short-circuit, you've reproduced `IsT1`/`AsT1` with extra ceremony — the exhaustiveness check is gone. Make each arm produce the final result type instead, threading the success continuation through the success arm:

```csharp
// Wrong — fork-extract via nullable
string? rejection = result.Match<string?>(_ => null, e => e.Value);
if (rejection is not null) return new PreconditionFailed(rejection);
// ...continue happy path...

// Right — both arms produce the final result
return await result.Match(
    _ => ContinueHappyPath(...),
    e => Task.FromResult<CommandResult<T>>(new PreconditionFailed(e.Value)));
```

### Name typed arms; discard only unit/None

`.Match` and `.Switch` arms are positional — the parameter name is the only inline documentation of which arm is which. In deeply-nested handler flows, the arm body alone rarely makes the discriminator obvious.

Discard (`_`) is appropriate only when the arm's type carries no information:
- `None` (e.g. the second arm of `MaybeAggregate<T>`)
- `Success` from `OneOf.Types`
- An empty marker arm with no fields

When the arm's type carries data, name the parameter — even if the body doesn't reference it. The name documents the arm's identity:

```csharp
// Wrong — both arms anonymous, reader has to reconstruct which fires when
return await existing.Match(
    _ => Task.FromResult<CommandResult<T>>(new Conflict("...already exists")),
    _ => ContinueHappyPath());

// Right — typed arm named, None discarded
return await existing.Match(
    found => Task.FromResult<CommandResult<T>>(new Conflict($"{found.Id} already exists")),
    _ => ContinueHappyPath());
```

The same applies to multi-arm OneOfs whose arms carry typed identity (per the rule above) — naming each typed arm is what makes typed-failure OneOfs readable. `_, _, _` collapses the very thing the typed union exists to surface.

### Trusted-input factories for serialization / migration paths

The need for `.AsSuccess()` / `.AsT0` usually signals a real underlying intent: the caller is on a path where the value is already known to be valid (Cosmos deserialisation of data we wrote, mapping from a pre-validated upstream record, JSON converter for a string we already round-tripped). Re-running the validation just to discard the failure adds nothing.

For these cases, expose a parallel non-OneOf factory:

```csharp
public static Percentage FromTrustedSource(decimal value) =>
    Create(value).Match(
        p => p,
        e => throw new InvalidOperationException($"Trusted source produced invalid Percentage: {e.Value}"));
```

The throw is a should-never-fire data-integrity guard, not control flow — call sites with no genuine domain failure to handle (deserializers, EF mappings, internal migrations) use this factory and stop swallowing errors silently. Anything that *might* legitimately receive invalid input continues to use `Create` and handle the failure properly.

### Carve-out: fold-with-short-circuit over a sequence

Iterating a collection with halt-on-first-failure has no idiomatic C# combinator. Manual `if (result.IsT1) return result.AsT1;` inside a `foreach` is permitted in this case only — keep the scope tight (one foreach, one explicit early return) and add a comment on the `if` line noting the carve-out so the next reader doesn't "fix" it. Alternatives are worse: `Aggregate` runs every element after the first failure; captured-flag + `break` reintroduces the nullable-flag smell.

## Aggregates

- `Aggregate<T>` base class provides `id` — don't redeclare.
- Use `[Newtonsoft.Json.JsonConstructor]` (not `System.Text.Json`) for Cosmos deserialization.
- Domain mutations: see "Domain mutations: failure arms must carry typed identity" above. Return a multi-arm OneOf whose failure arms each carry typed identity. `OneOf<Success, Error<string>>` is forbidden on new mutations; existing sites are migrating. `void`+throw is not an acceptable replacement.
- `Freemarket.Currency` is a struct from external package — use `.ToString()` for string comparisons, `new Currency(value)` to construct.

## MaybeAggregate Pattern

Use `MaybeGetById` + `Match` for safe retrieval in queries:

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

## Value Object Pattern

Use `record` (record class) with private constructor and `Create` factory returning `OneOf<T, Error<string>>`:

```csharp
public record Percentage
{
    public decimal Value { get; }

    [JsonConstructor]
    private Percentage(decimal value) => Value = value;

    public static OneOf<Percentage, Error<string>> Create(decimal value)
    {
        if (value < 0) return new Error<string>(Errors.TooLow);
        if (value > 1) return new Error<string>(Errors.TooHigh);
        return new Percentage(value);
    }

    public static Percentage FromTrustedSource(decimal value) =>
        Create(value).Match(
            p => p,
            e => throw new InvalidOperationException($"Trusted source produced invalid Percentage: {e.Value}"));

    public static implicit operator decimal(Percentage percentage) => percentage.Value;

    public static class Errors
    {
        public const string TooLow = "Cannot be below 0%";
        public const string TooHigh = "Cannot be above 100%";
    }
}
```

Rules:
- **`record`** (class, not struct) — value equality, immutable, compiler-enforced null safety.
- **Private ctor** — forces creation through `Create` or `FromTrustedSource`. `[JsonConstructor]` allows deserialization.
- **`OneOf<T, Error<string>>` return on `Create`** — no exceptions for invalid input; callers `.Match()` both cases. Audit shows callers do not branch on the specific error message; the string is propagated to a 422 response. Multi-arm named-failure OneOfs were considered and rejected as over-engineering for this consumption pattern.
- **`FromTrustedSource` for known-valid inputs** — deserializers, EF mappings, and migration paths use this factory instead of `.AsSuccess()` / `.AsT0`. The throw is a data-integrity guard.
- **`Errors` static class** — string constants so callers can match on specific errors when they need to (rare in practice).
- **Implicit operator** — optional, for unwrapping convenience.
- **Why not `readonly record struct`?** — structs always have a default value; `default(T)` / `new T()` zeroes fields and bypasses `Create`.
- **Serialization pitfall** — after renaming/adding properties, verify `[JsonPropertyName]` matches. Cosmos reads silently return `default` for mismatched names.
