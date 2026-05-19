---
name: bdd-test
description: "Scaffold a BDD unit test with specs and steps. Use for domain or developer tests. Triggers on: create bdd test, add unit test, scaffold test, new test."
license: MIT
---

# BDD Test Scaffolder

Create BDD-style unit tests using the Specification pattern.

---

## The Job

1. Get test subject and scenarios from user
2. Find existing test examples
3. Create specs and steps files
4. Ensure tests pass

**Important:** Use `Freemarket.Testing.Bdd.Specification` as base class. Never use `Freemarket.Bdd`.

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
- What class/method to test
- Module name
- Key scenarios to cover

---

## Step 2: Find Examples

Search for existing BDD tests:

```bash
# Find existing specs
find test -name "*.Specs.cs" -path "*/Developer/*" -o -name "*.Specs.cs" -path "*/Domain/*" | head -5

# Find Specification usage
grep -l "Specification" test -r --include="*.cs" | head -5
```

Read 1-2 examples to understand the exact patterns used.

---

## Step 3: Create Files

Create in `test/{Module}.Tests/Developer/` or `test/{Module}.Tests/Domain/`:

### 1. {ClassName}Specs.cs

```csharp
using Freemarket.Testing.Bdd;
using Xunit;

namespace {Module}.Tests.Developer;

public partial class {ClassName}Specs : Specification
{
    [Fact]
    public async Task {MethodName}_ValidInput_ReturnsExpectedResult()
    {
        Given(AValidInput);
        await WhenAsync(ExecutingTheMethod);
        Then(ResultIsAsExpected);
    }

    [Fact]
    public async Task {MethodName}_InvalidInput_ThrowsException()
    {
        Given(AnInvalidInput);
        await WhenAsync(ExecutingTheMethod);
        Then(ExceptionIsThrown);
    }

    [Fact]
    public void {MethodName}_EdgeCase_HandlesCorrectly()
    {
        Given(AnEdgeCaseInput);
        When(ExecutingTheMethod);
        Then(EdgeCaseIsHandled);
    }
}
```

### 2. {ClassName}Steps.cs

```csharp
using FluentAssertions;
using {Module}.Application.Features;

namespace {Module}.Tests.Developer;

public partial class {ClassName}Specs
{
    private {ClassName}? _sut;
    private {InputType}? _input;
    private {OutputType}? _result;
    private Exception? _exception;

    private void AValidInput()
    {
        _input = new {InputType}(
            Id: Guid.NewGuid(),
            Name: "Test");

        _sut = new {ClassName}(/* dependencies */);
    }

    private void AnInvalidInput()
    {
        _input = new {InputType}(
            Id: Guid.Empty,
            Name: string.Empty);

        _sut = new {ClassName}(/* dependencies */);
    }

    private void AnEdgeCaseInput()
    {
        _input = new {InputType}(
            Id: Guid.NewGuid(),
            Name: new string('x', 1000));  // Very long name

        _sut = new {ClassName}(/* dependencies */);
    }

    private async Task ExecutingTheMethod()
    {
        try
        {
            _result = await _sut!.{MethodName}(_input!);
        }
        catch (Exception ex)
        {
            _exception = ex;
        }
    }

    private void ExecutingTheMethodSync()
    {
        try
        {
            _result = _sut!.{MethodName}(_input!);
        }
        catch (Exception ex)
        {
            _exception = ex;
        }
    }

    private void ResultIsAsExpected()
    {
        _exception.Should().BeNull();
        _result.Should().NotBeNull();
        _result.Should().BeEquivalentTo(new
        {
            Id = _input!.Id,
            Name = _input.Name
        });
    }

    private void ExceptionIsThrown()
    {
        _exception.Should().NotBeNull();
        _exception.Should().BeOfType<ValidationException>();
    }

    private void EdgeCaseIsHandled()
    {
        _exception.Should().BeNull();
        _result.Should().NotBeNull();
    }
}
```

---

## Step 4: Test Naming Convention

Follow Microsoft's three-part naming: `[MethodName]_[Scenario]_[ExpectedBehavior]`

```csharp
// Good
HandleAsync_ValidRequest_ReturnsSuccess()
HandleAsync_InvalidId_ThrowsNotFoundException()
Calculate_NegativeInput_ReturnsZero()

// Bad
Test_Single()
HandleTest()
ShouldWork()
```

---

## Step 5: Run Tests

```bash
dotnet run --project ./test/{Module}.Tests/{Module}.Tests.csproj --no-build --configuration Release -- --filter "FullyQualifiedName~{ClassName}Specs"
```

Fix any failing tests before completing.

---

## Test Doubles

Do NOT use mocking libraries. Create hand-written fakes/spies:

```csharp
public class SpyCommandProcessor : IAmACommandProcessor
{
    public List<IRequest> SentCommands { get; } = [];

    public async Task SendAsync<T>(T command, CancellationToken ct = default) where T : class, IRequest
    {
        SentCommands.Add(command);
    }

    // Implement other interface methods as needed
}
```

Look for existing test doubles in `Tests.Shared` before creating new ones.

---

## Assertion Patterns

Use FluentAssertions. Prefer `BeEquivalentTo` over multiple assertions:

```csharp
// Good - single equivalence assertion
result.Should().BeEquivalentTo(new
{
    Id = expectedId,
    Name = "Expected",
    Status = Status.Active
});

// Avoid - multiple individual assertions
result.Id.Should().Be(expectedId);
result.Name.Should().Be("Expected");
result.Status.Should().Be(Status.Active);

// Good - for collections
results.Should().BeEquivalentTo([
    new { Id = 1, Name = "First" },
    new { Id = 2, Name = "Second" }
]);
```

---

## Checklist

- [ ] Specs file uses `Freemarket.Testing.Bdd.Specification` (NOT `Freemarket.Bdd`)
- [ ] Uses xUnit `[Fact]` or `[Theory]` (NOT NUnit)
- [ ] Test names follow `Method_Scenario_Expected` pattern
- [ ] Steps file has corresponding Given/When/Then methods
- [ ] Uses FluentAssertions with `Should().BeEquivalentTo()`
- [ ] No mocking libraries - hand-written test doubles only
- [ ] Tests pass
