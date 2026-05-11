# OpenAPI / DTO Shape

Applies to endpoint signatures, request DTOs, and any record bound via `[AsParameters]` or accepted as a body. Targets .NET 10 build-time OpenAPI generation.

## `[AsParameters]` query records: use `[ParameterDescription]`

Never stack `[System.ComponentModel.Description]` with `[FromQuery]` on a query parameter — neither on a positional record param nor on a direct method parameter. .NET 10's OpenAPI generator hits an `InvalidCastException` on the `ParameterInfo` path (aspnetcore#43395) and breaks the scheduled `Update OpenAPI Specs` pipeline.

Use `Freemarket.OpenApi.ParameterDescription` instead, on a property declaration inside an `[AsParameters]`-bound record with init-only properties:

```csharp
using Freemarket.OpenApi;

public record GetThingsRequest
{
    [ParameterDescription("Filter by source account")]
    [FromQuery]
    public Guid? SourceAccountId { get; init; }

    [ParameterDescription("Page number")]
    [FromQuery]
    [Range(1, int.MaxValue)]
    public int? Page { get; init; }
}

public static async Task<...> Handle(
    [AsParameters] GetThingsRequest request,
    ...) { ... }
```

- **Direct method parameters have no property workaround** — `ParameterInfo` is always `ParameterInfo`. If you need to describe a query param, you MUST wrap it in an `[AsParameters]` record.
- **Positional record params are forbidden** for query records. Reshape to init-only properties so each attribute lives on a property declaration, not a parameter.
- **Package** — requires `Freemarket.OpenApi` ≥ 14.6.0. Add a direct `<PackageReference Include="Freemarket.OpenApi" />` to the consuming Application project (version is centrally managed via `Directory.Packages.props`).

## Optional query params must be nullable + coalesced

ASP.NET's `[AsParameters]` parameter binder does NOT treat an init-only property with `= default` (or any default value) as optional — the OpenAPI spec emits the param as `required: true`, and a missing value returns a 400 "required parameter" instead of letting `[Range]` or FluentValidation produce the intended 422.

```csharp
// Wrong — Page appears required in the OpenAPI spec
public int Page { get; init; } = 1;

// Right — nullable + coalesce in the endpoint
public int? Page { get; init; }

// In endpoint:
new GetThingsQuery(..., request.Page ?? 1, request.PageSize ?? 20);
```

`[Range]` still triggers 422 for out-of-range values; FluentValidation continues to enforce the same bounds on the query.

## Body request DTOs: init-only, no stacked attributes on positional params

For request bodies (POST/PUT), use init-only properties and put each attribute on the property declaration:

```csharp
public record CreateThingRequest
{
    [Description("Unique identifier")]
    public required Guid Id { get; init; }

    [Description("Display name")]
    [MinLength(1)]
    [MaxLength(100)]
    public required string Name { get; init; }
}
```

Stacking multiple attribute types on positional record parameters crashes .NET 10 build-time OpenAPI generation. Response DTOs that inherit `HateoasResource` may remain positional provided each parameter has **at most one** attribute.

Annotations here are for OpenAPI only — validation rules still live in the `FluentValidation` `AbstractValidator<T>` and must match.
