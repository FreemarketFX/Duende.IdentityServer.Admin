---
name: feature
description: "Generates a command endpoint comprising handler, validator, and DTOs for POST/PUT/DELETE operations. Activated on: feature generation, command wiring."
license: MIT
---

# Feature Scaffolder

Create a complete command endpoint with all required files following the modular monolith patterns.

---

## The Job

1. Get feature name and details from user
2. Find existing examples in the codebase
3. Create all required files in the feature folder
4. Ensure build passes

**Important:** Follow existing patterns in the codebase exactly.

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
- Feature name (e.g., "CreateOrder", "UpdateCustomer")
- Module name (which bounded context)
- Brief description of what it does

---

## Step 2: Find Examples

Search for existing command endpoints to follow their patterns:

```bash
# Find existing handlers
find src -name "*.Handler.cs" -path "*/Application/*" | head -5

# Find existing endpoints
find src -name "*.Endpoint.cs" -path "*/Application/*" | head -5
```

Read 1-2 examples to understand the exact patterns used.

---

## Step 3: Create Files

Create these files in `src/{Module}/Application/Features/{FeatureName}/`:

### 1. {FeatureName}.Endpoint.cs

```csharp
namespace {Module}.Application.Features;

public static class {FeatureName}Endpoint
{
    public const string Route = "/api/{module}/{resource}";

    public static IEndpointRouteBuilder Map{FeatureName}(this IEndpointRouteBuilder app)
    {
        app.MapPost(Route, Handle)
            .WithName(nameof({FeatureName}))
            .WithTags("{Module}")
            .Produces<{FeatureName}Response>(StatusCodes.Status201Created)
            .ProducesProblem(StatusCodes.Status400BadRequest)
            .ProducesProblem(StatusCodes.Status401Unauthorized)
            .ProducesProblem(StatusCodes.Status403Forbidden)
            .ProducesProblem(StatusCodes.Status422UnprocessableEntity);

        return app;
    }

    private static async Task<IResult> Handle(
        [FromBody] {FeatureName}Request request,
        [FromServices] IAmACommandProcessor commandProcessor,
        [FromServices] CommandResultHandler resultHandler,
        CancellationToken ct)
    {
        {FeatureName}Command command = new(request.Id, request.Name);
        await commandProcessor.SendAsync(command, cancellationToken: ct);
        return resultHandler.Handle(command.Result, nameof({FeatureName}), new { id = request.Id });
    }
}
```

### 2. {FeatureName}.Handler.cs

```csharp
namespace {Module}.Application.Features;

public class {FeatureName}Command(Guid id, string name) : Command
{
    public Guid Id { get; } = id;
    public string Name { get; } = name;
}

[LoadPermissions]
public class {FeatureName}Handler(
    IRepository repository,
    ILogger<{FeatureName}Handler> logger)
    : BaseServiceRequestHandlerAsync<{FeatureName}Command>
{
    public override async Task<{FeatureName}Command> HandleAsync(
        {FeatureName}Command command,
        CancellationToken ct = default)
    {
        if (!command.Permissions.HasPermission("{Module}.Write"))
        {
            command.Result = new Forbidden();
            return command;
        }

        // Implementation here
        Domain.{Aggregate} aggregate = new(command.Id, command.Name);
        await repository.Add(aggregate, ct);

        {FeatureName}Response response = new(aggregate.Id);
        command.Result = response.ToCreated();
        return command;
    }
}
```

### 3. {FeatureName}.Dtos.cs

```csharp
using System.ComponentModel;
using System.ComponentModel.DataAnnotations;

namespace {Module}.Application.Features;

public record {FeatureName}Request
{
    [Description("Unique identifier")]
    public required Guid Id { get; init; }

    [Description("Display name")]
    [MinLength(1)]
    [MaxLength(100)]
    public required string Name { get; init; }
}

public record {FeatureName}Response(Guid Id) : HateoasResource(
    [new(nameof({FeatureName}Endpoint), {FeatureName}Endpoint.Route, new { id = Id })]);
```

### 4. {FeatureName}.Validator.cs

```csharp
using FluentValidation;

namespace {Module}.Application.Features;

public class {FeatureName}Validator : AbstractValidator<{FeatureName}Command>
{
    public {FeatureName}Validator()
    {
        RuleFor(x => x.Id)
            .NotEmpty();

        RuleFor(x => x.Name)
            .NotEmpty()
            .MaximumLength(100);
    }
}
```

---

## Step 4: Register Endpoint

Find the module's endpoint registration file using `Glob("src/{Module}/**/Endpoints.cs")` (filename typically `Endpoints.cs` or `{Module}Endpoints.cs`). Open it and add the mapping call alongside the existing `app.Map*()` calls:

```csharp
app.Map{FeatureName}();
```

If Glob returns no match, ask the user where the module registers its endpoints — do not create a new file speculatively.

---

## Step 5: Verify

```bash
dotnet build --configuration Release /p:NetCoreBuild=true
```

Fix any build errors before completing.

---

## Checklist

- [ ] All 4 files created in correct location
- [ ] Followed existing patterns from codebase
- [ ] DTOs have OpenAPI annotations matching validator rules
- [ ] Endpoint registered in module
- [ ] Build passes
- [ ] No async suffix on method names
