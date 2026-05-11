---
name: query
description: "Scaffolds a read-model GET route with request/response types. Invoked when: query scaffolding, GET route needed."
license: MIT
---

# Query Scaffolder

Create a complete query endpoint with handler and response following the modular monolith patterns.

---

## The Job

1. Get query name and details from user
2. Find existing examples in the codebase
3. Create all required files in the feature folder
4. Ensure build passes

**Important:** Use MaybeAggregate pattern for GET by ID queries.

---

## Step 0: Load Project Rules

Before writing any code, re-read the project's coding rules so they are fresh in context:

1. **Find CLAUDE.md**: Run `Glob("CLAUDE.md")` from the repo root. If not found, try `Glob("**/CLAUDE.md")` and take the first match not inside `claude-shared/`, `node_modules/`, or `.claude/`.
2. **Extract rules**: Look for a "Common Review Feedback" section. If it exists, treat every bullet as a hard constraint on the code you are about to write. Also read any Testing, Code Style, and Architecture sections.
3. **Check for MEMORY.md**: Run `Glob("MEMORY.md")` from the repo root. If found, read it and follow links to any `feedback` type entries.
4. **Carry forward**: Keep these rules as a checklist. Cross-reference each generated file against them before presenting it.

If no repo-level CLAUDE.md is found, skip this step.

---

## Step 1: Gather Information

Ask the user:
- Query name (e.g., "GetOrder", "GetCustomerById")
- Module name (which bounded context)
- What entity/aggregate is being queried
- Whether it's a single item or list query

---

## Step 2: Find Examples

Search for existing query endpoints:

```bash
# Find existing queries
find src -name "*.Query.cs" -path "*/Application/*" | head -5

# Find existing query handlers
grep -l "QueryHandlerAsync" src -r --include="*.cs" | head -5
```

Read 1-2 examples to understand the exact patterns used.

---

## Step 3: Create Files

Create these files in `src/{Module}/Application/Features/{QueryName}/`:

### 1. {QueryName}.Endpoint.cs

```csharp
namespace {Module}.Application.Features;

public static class {QueryName}Endpoint
{
    public const string Route = "/api/{module}/{resource}/{id}";

    public static IEndpointRouteBuilder Map{QueryName}(this IEndpointRouteBuilder app)
    {
        app.MapGet(Route, Handle)
            .WithName(nameof({QueryName}))
            .WithTags("{Module}")
            .Produces<{QueryName}Response>()
            .ProducesProblem(StatusCodes.Status401Unauthorized)
            .ProducesProblem(StatusCodes.Status403Forbidden)
            .ProducesProblem(StatusCodes.Status404NotFound);

        return app;
    }

    private static async Task<IResult> Handle(
        [FromRoute] Guid id,
        [FromServices] IQueryProcessor queryProcessor,
        [FromServices] QueryResultHandler resultHandler,
        CancellationToken ct)
    {
        {QueryName}Query query = new(id);
        QueryResult<{QueryName}Response> result = await queryProcessor.ExecuteAsync(query, ct);
        return resultHandler.Handle(result);
    }
}
```

### 2. {QueryName}.Query.cs

```csharp
namespace {Module}.Application.Features;

public record {QueryName}Query(Guid Id) : IQuery<QueryResult<{QueryName}Response>>;

[LoadPermissions]
public class {QueryName}Handler(
    IRepository repository,
    ILogger<{QueryName}Handler> logger)
    : QueryHandlerAsync<{QueryName}Query, QueryResult<{QueryName}Response>>
{
    public override async Task<QueryResult<{QueryName}Response>> ExecuteAsync(
        {QueryName}Query query,
        CancellationToken ct = default)
    {
        if (!query.Permissions.HasPermission("{Module}.Read"))
        {
            return new Forbidden();
        }

        var aggregate = await repository.MaybeGetById<Domain.{Aggregate}>($"{query.Id}");

        return aggregate.Match<QueryResult<{QueryName}Response>>(
            agg => new Success<{QueryName}Response>(new(agg.Id, agg.Name)),
            _ => new NotFound { Message = $"{Aggregate} {query.Id} not found" }
        );
    }
}
```

### 3. {QueryName}.Response.cs

```csharp
using System.ComponentModel;

namespace {Module}.Application.Features;

public record {QueryName}Response(
    [Description("Unique identifier")] Guid Id,
    [Description("Display name")] string Name)
    : HateoasResource([new(nameof({QueryName}Endpoint), {QueryName}Endpoint.Route, new { id = Id })]);
```

---

## Step 4: Register Endpoint

Add to the module's endpoint registration:

```csharp
app.Map{QueryName}();
```

---

## Step 5: Verify

```bash
dotnet build --configuration Release /p:NetCoreBuild=true
```

Fix any build errors before completing.

---

## MaybeAggregate Pattern

Always use `MaybeGetById` + `Match` for single-item queries:

```csharp
var aggregate = await repository.MaybeGetById<Domain.MyAggregate>($"{query.Id}");

return aggregate.Match<QueryResult<MyResponse>>(
    agg => new Success<MyResponse>(new(agg.Id, agg.Name)),
    _ => new NotFound { Message = $"MyAggregate {query.Id} not found" }
);
```

- First lambda = found case
- Second lambda = not found case
- Forces handling both cases at compile time

---

## Checklist

- [ ] All 3 files created in correct location
- [ ] Used MaybeAggregate pattern for single-item queries
- [ ] Response has OpenAPI annotations
- [ ] Endpoint registered in module
- [ ] Build passes
- [ ] No async suffix on method names
