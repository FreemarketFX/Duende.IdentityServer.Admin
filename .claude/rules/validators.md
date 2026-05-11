# Validators

Applies to `*.Validator.cs`.

## Null Safety

Any string operation on a request field (`.ToUpperInvariant()`, `.ToLower*`, `.Trim`, `.Split`, `.StartsWith`, `.Length`) MUST be null-guarded. `NotEmpty` + `RuleForEach` rules run independently and do NOT always short-circuit, so a single null in a JSON payload NREs the whole request.

Guard via `.Where(x => x.Field is not null)` before a projection, or `.When(x => x.Field is not null, ...)` around the rule.

## Near-Duplicate Validators

When a second validator is ≥80% identical to an existing one (same rule set on similar DTOs), extract the shared rules. Don't copy-paste.

Pattern: define an interface (e.g. `IAcceptanceRequest`) that both DTOs implement, then an extension method (`AbstractValidator<T>.AddSharedRules()`) that applies the shared rules. Both validators collapse to a single call.

## Sharing State With Handler

If the validator needs the same entity the handler fetches, read it from `command.RootContextData["entity"]` — see endpoints rule.
