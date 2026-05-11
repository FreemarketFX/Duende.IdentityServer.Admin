---
name: integration-test
description: "Scaffold an API integration test with specs and steps. Required for new endpoints. Triggers on: create integration test, add api test, test endpoint, scaffold integration test."
license: MIT
---

# Integration Test Scaffolder

Create API integration tests for endpoints using BDD pattern.

---

## The Job

1. Get endpoint details from user
2. Find existing integration test examples
3. Create specs and steps files
4. Ensure tests pass

**Important:** Every new endpoint requires integration tests for happy path + 401 unauthorized.

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
- Which endpoint to test
- Module name
- What the happy path scenario is

---

## Step 2: Find Examples

Search for existing integration tests:

```bash
# Find existing integration test specs
find test -name "*.Specs.cs" -path "*/Integration/*" | head -5

# Find ApiSpecification usage
grep -l "ApiSpecification" test -r --include="*.cs" | head -5
```

Read 1-2 examples to understand the exact patterns used.

---

## Step 3: Create Files

Create in `test/{Module}.Tests/Integration/`:

### 1. {FeatureName}.Specs.cs

```csharp
using Xunit;
using Xunit.Abstractions;

namespace {Module}.Tests.Integration;

[Collection({Module}ApiCollection.Name)]
public partial class {FeatureName}Specs(ApiFixture fixture, ITestOutputHelper outputHelper)
    : ApiSpecification(fixture, outputHelper)
{
    [Fact]
    public async Task {FeatureName}_ValidRequest_ReturnsSuccess()
    {
        Given(AValidRequest);
        await WhenAsync(SendingTheRequest);
        Then(ResponseIsSuccessful);
    }

    [Fact]
    public async Task {FeatureName}_NoAuth_ReturnsUnauthorized()
    {
        Given(AValidRequest);
        Given(NoAuthentication);
        await WhenAsync(SendingTheRequest);
        Then(ResponseIsUnauthorized);
    }
}
```

### 2. {FeatureName}.Steps.cs

```csharp
using System.Net;
using System.Net.Http.Json;
using FluentAssertions;
using {Module}.Application.Features;

namespace {Module}.Tests.Integration;

public partial class {FeatureName}Specs
{
    private {FeatureName}Request? _request;
    private HttpResponseMessage? _response;
    private bool _useAuth = true;

    private void AValidRequest()
    {
        _request = new {FeatureName}Request(
            Id: Guid.NewGuid(),
            Name: "Test Name");
    }

    private void NoAuthentication()
    {
        _useAuth = false;
    }

    private async Task SendingTheRequest()
    {
        HttpClient client = _useAuth
            ? RequestHelperWithAuth()
            : RequestHelperWithoutAuth();

        _response = await client.PostAsJsonAsync(
            {FeatureName}Endpoint.Route,
            _request);
    }

    private void ResponseIsSuccessful()
    {
        _response.Should().NotBeNull();
        _response!.StatusCode.Should().Be(HttpStatusCode.Created);
    }

    private void ResponseIsUnauthorized()
    {
        _response.Should().NotBeNull();
        _response!.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }
}
```

---

## Step 4: For GET Endpoints

Adjust the steps for query endpoints:

```csharp
// In Steps file
private Guid _resourceId;

private async Task AResourceExists()
{
    // Create the resource first via the API or directly in the database
    _resourceId = Guid.NewGuid();
    // Setup code here
}

private async Task SendingTheRequest()
{
    HttpClient client = _useAuth
        ? RequestHelperWithAuth()
        : RequestHelperWithoutAuth();

    string route = {QueryName}Endpoint.Route.Replace("{id}", _resourceId.ToString());
    _response = await client.GetAsync(route);
}

private void ResponseIsSuccessful()
{
    _response.Should().NotBeNull();
    _response!.StatusCode.Should().Be(HttpStatusCode.OK);
}
```

---

## Step 5: Run Tests

```bash
dotnet run --project ./test/{Module}.Tests/{Module}.Tests.csproj --no-build --configuration Release -- --filter "FullyQualifiedName~{FeatureName}Specs"
```

Fix any failing tests before completing.

---

## Test Helpers

- `RequestHelperWithAuth()` - Returns HttpClient with authentication
- `RequestHelperWithoutAuth()` - Returns HttpClient without authentication
- `ApiFixture` - Provides `WebApplicationFactory<Program>`
- `ApiSpecification` - Base class with Given/When/Then helpers

---

## Required Tests

Every endpoint must have at minimum:

1. **Happy path** - Valid request returns expected success response
2. **401 Unauthorized** - Request without auth returns 401

Consider also:
- 400 Bad Request - Invalid input
- 403 Forbidden - Auth but no permission
- 404 Not Found - Resource doesn't exist (for GET/PUT/DELETE)
- 422 Unprocessable Entity - Validation failure

---

## Checklist

- [ ] Specs file with `[Collection]` attribute
- [ ] Inherits from `ApiSpecification`
- [ ] Happy path test
- [ ] 401 unauthorized test
- [ ] Steps file with Given/When/Then methods
- [ ] Uses `FluentAssertions` with `Should().BeEquivalentTo()` where appropriate
- [ ] Tests pass
