---
name: architecture-test
description: "Scaffold module dependency isolation tests using NetArchTest. Generates assembly marker interfaces and ModuleDependencyTests.cs. Triggers on: architecture test, module isolation, dependency test, scaffold arch test."
license: MIT
---

# Architecture Test Scaffolder

Scaffold module boundary enforcement tests using NetArchTest.Rules. Generates assembly marker interfaces and a `ModuleDependencyTests.cs` test class that verifies no module depends on another.

---

## The Job

1. Discover the module structure and existing architecture tests
2. Detect which test pattern the repo already uses
3. Create assembly marker interfaces in each layer
4. Create the test class matching the repo's pattern
5. Verify tests pass

---

## Step 0: Load Project Rules

Before writing any code, re-read the project's coding rules so they are fresh in context:

1. **Find CLAUDE.md**: Run `Glob("CLAUDE.md")` from the repo root. If not found, try `Glob("**/CLAUDE.md")` and take the first match not inside `claude-shared/`, `node_modules/`, or `.claude/`.
2. **Extract rules**: Look for Architecture, Testing, and Code Style sections. Treat every bullet as a constraint.
3. **Check for MEMORY.md**: Run `Glob("MEMORY.md")` from the repo root. If found, read it and follow links to any `feedback` type entries.
4. **Carry forward**: Keep these rules as a checklist. Cross-reference each generated file against them before presenting it.

If no repo-level CLAUDE.md is found, skip this step.

---

## Step 1: Gather Information

Ask the user:
- **Module name** (e.g. `AccountBalances`, `Screening`, `Clients`)
- **Which other modules should be forbidden** (or auto-discover)

Then auto-discover the structure:

```bash
# Find all module directories under src/
ls src/

# Find all test projects
find test -name "*.csproj" | head -20

# Find the solution file
ls *.slnx *.sln 2>/dev/null
```

Determine which layers the module has by checking for these directories:
- `src/{Module}/Application/` or `src/{Module}.Application/`
- `src/{Module}/Domain/` or `src/{Module}.Domain/`
- `src/{Module}/Migrations/` or `src/{Module}.Migrations/`
- `src/{Module}/Infrastructure/`

---

## Step 2: Find Existing Patterns

Search for existing architecture tests to match the repo's style:

```bash
# Find existing architecture/dependency tests
grep -rl "ShouldNot.*HaveDependencyOn" test/ --include="*.cs" | head -5

# Find existing assembly markers
grep -rl "AssemblyMarker" src/ --include="*.cs" | head -5

# Find existing module dependency tests
find test -name "ModuleDependencyTests.cs" -o -name "ModuleIsolationTests.cs" | head -5
```

Read 1-2 existing test files to understand the exact pattern. Two known patterns exist:

### Pattern A — Theory-based (simpler, preferred)

Used in ClientActions. Each forbidden module is an `[InlineData]` argument:

```csharp
using FluentAssertions;
using NetArchTest.Rules;
using Xunit;

namespace {Module}.Tests.Architecture;

public class ModuleDependencyTests
{
    [Theory]
    [InlineData("ForbiddenModule1")]
    [InlineData("ForbiddenModule2")]
    public void Application_ShouldNotDependOn(string forbiddenModule)
    {
        Types.InAssembly(typeof(I{Module}Application).Assembly)
            .ShouldNot()
            .HaveDependencyOn(forbiddenModule)
            .GetResult()
            .IsSuccessful
            .Should()
            .BeTrue($"{Module}.Application should not reference {forbiddenModule}");
    }

    [Theory]
    [InlineData("ForbiddenModule1")]
    [InlineData("ForbiddenModule2")]
    public void Domain_ShouldNotDependOn(string forbiddenModule)
    {
        Types.InAssembly(typeof(I{Module}Domain).Assembly)
            .ShouldNot()
            .HaveDependencyOn(forbiddenModule)
            .GetResult()
            .IsSuccessful
            .Should()
            .BeTrue($"{Module}.Domain should not reference {forbiddenModule}");
    }
}
```

### Pattern B — Namespace-based with helper (fuller)

Used in ComplianceMonolith. Checks namespace dependencies and assembly-level references:

```csharp
using System.Reflection;
using FluentAssertions;
using NetArchTest.Rules;
using Xunit;

namespace {Module}.Tests.Architecture;

public class ModuleIsolationTests
{
    private static readonly Assembly ApplicationAssembly = typeof(I{Module}ApplicationAssemblyMarker).Assembly;
    private static readonly Assembly DomainAssembly = typeof(I{Module}DomainAssemblyMarker).Assembly;
    private static readonly Assembly MigrationsAssembly = typeof(I{Module}MigrationsAssemblyMarker).Assembly;

    private static readonly Assembly[] AllAssemblies =
    [
        ApplicationAssembly,
        DomainAssembly,
        MigrationsAssembly,
    ];

    private static readonly string[] ForbiddenNamespaces =
    [
        "OtherModule",
    ];

    [Fact]
    public void Application_ShouldNotDependOn_ForbiddenNamespaces()
    {
        NetArchTest.Rules.TestResult result = Types.InAssembly(ApplicationAssembly)
            .ShouldNot()
            .HaveDependencyOnAny(ForbiddenNamespaces)
            .GetResult();

        result.IsSuccessful.Should().BeTrue(
            $"{Module}.Application should not depend on forbidden namespaces. " +
            $"Violating types: {FormatViolatingTypes(result)}");
    }

    [Fact]
    public void Domain_ShouldNotDependOn_ForbiddenNamespaces()
    {
        NetArchTest.Rules.TestResult result = Types.InAssembly(DomainAssembly)
            .ShouldNot()
            .HaveDependencyOnAny(ForbiddenNamespaces)
            .GetResult();

        result.IsSuccessful.Should().BeTrue(
            $"{Module}.Domain should not depend on forbidden namespaces. " +
            $"Violating types: {FormatViolatingTypes(result)}");
    }

    [Fact]
    public void Assemblies_ShouldNotReference_ForbiddenAssemblies()
    {
        List<string> violations = [];

        foreach (Assembly assembly in AllAssemblies)
        {
            AssemblyName[] referencedAssemblies = assembly.GetReferencedAssemblies();
            IEnumerable<AssemblyName> forbidden = referencedAssemblies
                .Where(a => a.Name != null &&
                    ForbiddenNamespaces.Any(ns =>
                        a.Name.StartsWith(ns, StringComparison.OrdinalIgnoreCase)));

            foreach (AssemblyName reference in forbidden)
            {
                violations.Add($"{assembly.GetName().Name} -> {reference.Name}");
            }
        }

        violations.Should().BeEmpty(
            $"{Module} assemblies should not reference forbidden assemblies. " +
            $"Violations: {string.Join(", ", violations)}");
    }

    private static string FormatViolatingTypes(NetArchTest.Rules.TestResult result)
    {
        if (result.FailingTypes == null || !result.FailingTypes.Any())
            return "none";

        return string.Join(", ", result.FailingTypes.Select(t => t.FullName));
    }
}
```

**Decision rule:** If the repo already has architecture tests, match that pattern exactly. If no existing tests, use Pattern A (simpler, easier to maintain).

---

## Step 3: Create Files

### Assembly Marker Interfaces

Create one marker per layer. Place in the root namespace file of each project.

**File:** `src/{Module}/Application/AssemblyMarker.cs` (or `src/{Module}.Application/AssemblyMarker.cs`)

```csharp
namespace {Module};

public interface I{Module}ApplicationAssemblyMarker;
```

**File:** `src/{Module}/Domain/AssemblyMarker.cs` (or `src/{Module}.Domain/AssemblyMarker.cs`)

```csharp
namespace {Module}.Domain;

public interface I{Module}DomainAssemblyMarker;
```

**File:** `src/{Module}/Migrations/AssemblyMarker.cs` (if migrations layer exists)

```csharp
namespace {Module}.Migrations;

public interface I{Module}MigrationsAssemblyMarker;
```

**Before creating:** Check if markers already exist:
```bash
grep -rl "AssemblyMarker" src/{Module}/ --include="*.cs"
```
Skip any layer that already has a marker.

**Important:** Match the namespace to the project's actual `RootNamespace` (check the `.csproj` for `<RootNamespace>` — if absent, it defaults to the project folder name).

### Marker Naming

Match the existing naming convention in the repo:
- If the repo uses `I{Module}Application` (short form, e.g. ClientActions) → use that
- If the repo uses `I{Module}ApplicationAssemblyMarker` (long form, e.g. ComplianceMonolith) → use that
- If no convention exists, use the short form: `I{Module}Application`

### Test Class

Create `test/{Module}.Tests/Architecture/ModuleDependencyTests.cs` (or `ModuleIsolationTests.cs` if that's the repo convention).

Use the appropriate pattern from Step 2. Replace all placeholders with actual module names and forbidden modules.

### Package Reference

Check the test project's `.csproj` for `NetArchTest.Rules`:

```bash
grep "NetArchTest" test/{Module}.Tests/*.csproj
```

If missing, add:
```xml
<PackageReference Include="NetArchTest.Rules" Version="1.3.2" />
```

Also check for `Freemarket.Testing.Architecture` — if present, the test class can extend `ArchitectureTest` base class (adds `[Trait("Category", "Architecture")]` automatically).

### Project References

The test project needs references to all layers being tested. Check and add if missing:

```xml
<ProjectReference Include="..\..\src\{Module}\Domain\{Module}.Domain.csproj" />
<ProjectReference Include="..\..\src\{Module}\Migrations\{Module}.Migrations.csproj" />
```

---

## Step 4: Build and Run Tests

```bash
# Build
dotnet build --configuration Release /p:NetCoreBuild=true

# Run only architecture tests
dotnet run --project ./test/{Module}.Tests/{Module}.Tests.csproj --no-build --configuration Release -- --filter-class "*ModuleDependencyTests"
```

If tests fail, the module has actual dependency violations. Report them to the user — they need to be fixed before the tests can pass.

---

## Step 5: xUnit v3 Gotcha

xUnit v3 defines `Xunit.TestResult` which conflicts with `NetArchTest.Rules.TestResult`. If using Pattern B, always fully qualify:

```csharp
NetArchTest.Rules.TestResult result = Types.InAssembly(...)
```

---

## Checklist

- [ ] Assembly markers exist for each layer (Application, Domain, Migrations)
- [ ] Marker namespaces match the project's `RootNamespace`
- [ ] Test class follows the repo's existing pattern (A or B)
- [ ] `NetArchTest.Rules` package is referenced in the test project
- [ ] Test project has `ProjectReference` to all layers under test
- [ ] Tests pass (or fail only on genuine dependency violations)
- [ ] `TestResult` is fully qualified if using Pattern B with xUnit v3
