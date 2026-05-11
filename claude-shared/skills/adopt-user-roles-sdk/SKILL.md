---
name: adopt-user-roles-sdk
description: "Adopt the PlatformCode UserRolesGrantHandler SDK in a modular monolith. Scaffolds IRolePermissionProvider per module, wires DI, adds subscription, migrates grants table, removes bespoke handlers. Triggers on: adopt user roles sdk, wire up user roles, add user roles handler, adopt grant handler."
license: MIT
---

# Adopt UserRolesGrantHandler SDK

Adopt the PlatformCode `UserRolesGrantHandler` SDK (`Freemarket.Application.UserRoles`) in a modular monolith. Each module implements `IRolePermissionProvider`; the SDK handles event deserialization, permission resolution, and atomic grant replacement.

**Reference:** [ADR-002](https://github.com/FreemarketFX/PlatformCode/blob/main/docs/adr/002-user-roles-grant-handler-sdk.md) | [ClientActions PR #265](https://github.com/FreemarketFX/ClientActions/pull/265) (first adopter — study `TransfersRolePermissionProvider.cs`, `ServiceCollectionExtensions.cs`, `HostBuilderExtensions.cs`, and the `0007` migration)

---

## The Job

1. **Audit** the codebase
2. **Present** a plan for user confirmation
3. **Execute** the adoption
4. **Verify** the build passes

Do NOT start changes until the audit is complete and the user confirms.

---

## Step 1: Audit

### 1a. Identify modules

Search for `*BrighterExtensions*.cs`, `*BrighterConfiguration*.cs`, `Endpoints.cs`, or `AssemblyMarker.cs` in `src/`.

### 1b. Detect grants table

Search SQL migrations for the grants table. Check:
- Table name and schema (varies: `[Shared].[Grants]`, `[Shared].[RoleGrants]`, `[Auth].[Grant]`)
- Timestamp column name (`CreatedAt`, `CreateAt`, or `CreatedOn`)
- Whether `GrantId` column exists (SDK requires it)
- Primary key structure

Confirm with the `UseGrantsFromSqlServer()` call in HostApp.

### 1c. Detect existing bespoke handler

Search for `UserRolesUpdatedEvent`, `UserRolesUpdatedEventHandler`, `RolePermissionMapping`, `RoleToPermissionsMap`, `BaseUserRolesUpdatedEventHandler`, `ApplyPermissionsDeltaCommand`.

If found, note files to remove. Check if the service also **publishes** `UserRolesUpdatedEvent` — the publisher side must be kept.

### 1d. Detect IPermissionProvider

Search for `IPermissionProvider` implementations and `FallbackAuthorizationPolicyProvider`. These are almost certainly dead code — see [IPermissionProvider Removal](#ipermissionprovider-removal) for the full trace. Default stance: remove unless you find an endpoint using `[Authorize("Module:Resource:Action")]`-style policy names.

### 1e. Detect shared project

Check for `src/Shared/` or `src/Common/`. If none exists, suggest creating one for cross-cutting concerns (RoleIds, shared migrations).

### 1f. Check package versions

The SDK requires `Freemarket.Application >= 8.0.0`. Read current version from csproj files.

### 1g. Read `.AddApplication()`

Read `HostBuilderExtensions.cs` for: subscription registration pattern, handler assemblies, `darkerDecorators`, `Constants.ServiceName`.

---

## Step 2: Present the Plan

```
## Adoption Plan for [ServiceName]

### Current State
- Modules: [list]
- Grants table: [schema].[table] (timestamp: [column], GrantId: [yes/no])
- Existing handler: [yes/no — describe]
- Freemarket.Application: [version]
- Shared project: [yes/no]

### Changes
1. Package upgrade — Freemarket.* → 8.0.0
2. Grants table migration — [what needs changing]
3. IRolePermissionProvider per module — [known/unknown/SQL-backed]
4. SDK wiring — AddUserRolesGrantHandler + subscription + handler assembly
5. Remove — [files to delete]
6. Tests — permission mapping BDD tests

### Gotchas
- [list]

Proceed? (Y/N)
```

---

## Step 3: Package Upgrade

Update ALL `Freemarket.*` packages to 8.0.0 — they're versioned together, mixing causes `NU1605` errors.

Watch for:
- Lowercase package names (`freemarket.Application`) — fix casing
- Separate version trains (do NOT update): `Freemarket.ExchangeRateProvider`, `Freemarket.Hateoas.PermissionAuth`, `Freemarket.Api`, `Freemarket.Testing.Architecture`
- Packages duplicated across module csprojs — consolidate into Shared

---

## Step 4: Grants Table Migration

The SDK's `GrantsDb` expects these columns:

| Column | Type | Notes |
|--------|------|-------|
| `GrantId` | `UNIQUEIDENTIFIER NOT NULL` | Add if missing. SDK inserts `Guid.CreateVersion7()`. |
| `UserOrClientId` | `NVARCHAR(50)` | Usually exists. Configurable via `SqlGrantStoreOptions.UserIdColumn`. |
| `Permission` | `NVARCHAR(100)` | Usually exists. |
| `ResourceType` | `NVARCHAR(100)` | May need widening from NVARCHAR(50). |
| `ResourceId` | `NVARCHAR(100)` | May need widening from NVARCHAR(50). |
| `CreatedOn` | `DATETIME NOT NULL` | SDK uses `GETUTCDATE()`. Rename from `CreatedAt`/`CreateAt`, change type from `DATETIMEOFFSET`/`DATETIME2`. |

Generate an idempotent migration. Must handle: add GrantId, rename timestamp, drop default constraint, alter type, recreate constraint. See ClientActions `0007-RenameGrantsCreatedAtToCreatedOn.sql` for the pattern.

---

## Step 5: Create Shared RoleIds

Not all roles are shared across services. Some are service-specific (e.g., `TransferApprover` only exists in ClientActions).

**Decision order — pick the first one that applies:**

1. If Step 1c found a bespoke handler with role GUIDs already in use: extract those GUIDs and use them as the starting list. Do not ask the user. Confirm the list in the Step 2 plan.
2. Otherwise, ask the user which roles this service needs. If they're unsure, offer to start with `Administrator` only as a placeholder and say mappings will be added when confirmed.

Only include roles that at least one module in this service maps to permissions. Start with the common platform roles and add service-specific ones as needed:

```csharp
namespace {SharedNamespace}.Auth;

public static class RoleIds
{
    // Common platform roles
    public static readonly Guid Administrator = Guid.Parse("A6DBD51A-8536-44A8-AA05-B8B690DF860E");
    public static readonly Guid CustomerSuccessManager = Guid.Parse("F856EF66-C43D-4460-A00D-35D8D87AD6A1");
    public static readonly Guid CustomerOperationsSpecialist = Guid.Parse("C47C0842-EF1A-475E-A643-5397DDC7D827");
    public static readonly Guid AccountUser = Guid.Parse("0AB28B2B-DB7B-4DC7-B226-6F4D6BF410D5");
    public static readonly Guid ClientAdmin = Guid.Parse("EA3E4F72-735F-47A2-A109-F96DBF6819B2");

    // Service-specific roles — add only what this service uses
    // public static readonly Guid TransferApprover = Guid.Parse("83F244B8-EA98-4002-A51A-282AE4A44EFC");
}
```

Place in `src/Shared/Application/Auth/` or equivalent. If no shared project exists, suggest creating one; otherwise place in HostApp.

---

## Step 6: Create IRolePermissionProvider per Module

For each module with a `Permissions.cs`, scaffold a provider in `{Module}/Application/Auth/`.

**Static (known mappings or migrating from bespoke handler):**
```csharp
using Freemarket.Application.UserRoles;
using Freemarket.PermissionAuth;
using {SharedNamespace}.Auth;

namespace {Module}.Auth;

public class {Module}RolePermissionProvider : IRolePermissionProvider
{
    public Task<IReadOnlyDictionary<Guid, IReadOnlySet<Permission>>> Get(CancellationToken cancellationToken)
    {
        IReadOnlyDictionary<Guid, IReadOnlySet<Permission>> mappings = new Dictionary<Guid, IReadOnlySet<Permission>>
        {
            [RoleIds.Administrator] = new HashSet<Permission> { Permissions.SomePermission },
        };
        return Task.FromResult(mappings);
    }
}
```

**SQL-backed (e.g., Organisation Users module with `RolePermissionsLookup` view):**
```csharp
public class {Module}RolePermissionProvider(IDb db) : IRolePermissionProvider
{
    public async Task<IReadOnlyDictionary<Guid, IReadOnlySet<Permission>>> Get(CancellationToken cancellationToken)
    {
        var results = await db.Query<RolePermissionRow>(
            "SELECT RoleId, Permission FROM [{Module}].[RolePermissionsLookup]", ...);
        // Convert to dictionary
    }
}
```

**Placeholder (unknown mappings):** Map only Administrator with all module permissions and add a comment: `// Role-to-permission mappings need to be fully defined for all roles.`

The SDK's `RolePermissionMappingValidation` throws at startup if any provider returns empty mappings — every provider needs at least one role.

---

## Step 7: Wire Up SDK in HostApp

In the permission setup (after `UseGrantsFromSqlServer()`):
```csharp
services.AddUserRolesGrantHandler(config);
```

In `.AddApplication()` subscriptions (wrap in inner array — the factory returns `[][]`):
```csharp
[UserRolesGrantExtensions.CreateUserRolesSubscription(tnp, Constants.ServiceName)]
```

In `.AddApplication()` assemblies:
```csharp
Assembly.GetAssembly(typeof(UserRolesUpdatedEventHandler))!
```

In `CreateResiliencePipelineRegistry()` — register the handler's retry pipeline:
```csharp
using Shared.Application.Resilience;

registry.AddStandardRetry<UserRolesUpdatedEvent>(
    UserRolesUpdatedEventHandler.ResiliencePipelineName, logger, config);
```

**This is required.** The handler has `[UseResiliencePipelineAsync(policy: "UserRolesRetryPipeline", step: 2)]` — without this registration, Brighter throws `KeyNotFoundException` at runtime when building the handler pipeline.

In `appsettings.json`:
```json
"UserRolesGrantHandler": { "Enabled": true }
```

Add `using Freemarket.Application.UserRoles;` where needed.

---

## Step 8: Remove Bespoke Implementation

### Remove
- Local `UserRolesUpdatedEvent`, `UserRolesUpdatedEventMapper`, `UserRolesUpdatedEventHandler`
- `RolePermissionMapping` / `RoleToPermissionsMap` static classes
- `BaseUserRolesUpdatedEventHandler` abstract class
- `ApplyPermissionsDeltaCommand` and handler (SDK uses atomic full-replace)
- `UserPermissionQueryHandler` / `RetrieveUserPermissionsQuery` (if only used by delta pattern)
- Local `GrantRecord` types, `FailingDb` test doubles
- Module-specific `UserRolesUpdatedEvent` subscription (now shared via `CreateUserRolesSubscription`)

### Keep
- `Permissions.cs`, `PermissionCollectionExtensions.cs` (read-side, unaffected)
- `UseGrantsFromSqlServer()` (read-side, unaffected)

### Publishers: switch to SDK event class

If this service **publishes** `UserRolesUpdatedEvent` (e.g., Organisation), offer to replace the local event class with the SDK's `Freemarket.Application.UserRoles.UserRolesUpdatedEvent`. This makes the SDK package the single source of truth for the contract — no drift between publisher and subscriber.

To switch:
1. Remove the local `UserRolesUpdatedEvent` class and mapper
2. Use `Freemarket.Application.UserRoles.UserRolesUpdatedEvent` when constructing the event for publication
3. Use `Freemarket.Application.UserRoles.UserRolesUpdatedEventMapper` for serialization
4. Replace any local `ResourceType` enum with `string` values (`"Tenant"`, `"Account"`, etc.) — the wire format is identical

The publication registration in `BrighterExtensions.CreatePublications()` stays, just referencing the SDK type instead of the local one.

### IPermissionProvider Removal

`IPermissionProvider` is dead code in all known monoliths. The only consumer is `PermissionPolicyProvider.GetPolicyAsync()` in PlatformCode, which is designed for `[Authorize("Module:Resource:Action")]` attribute-based auth. No monolith uses this pattern — all use `LoadPermissionsDecorator` + `command.Permissions.HasPermission()` instead.

| Monolith | Registered? | Invoked at runtime? | Verdict |
|----------|------------|-------------------|---------|
| ClientActions | Was registered | Never invoked | **Removed** |
| MoneyMovement | Yes | Nothing resolves it | **Dead — remove** |
| Organisation | No | N/A | Already clean |
| ComplianceMonolith | Yes, via `FallbackAuthorizationPolicyProvider` | Invoked but always returns null — no permission-named policies exist | **Functionally dead — remove both** |

**Verify before removing:** search for `[Authorize("` and `RequireAuthorization("` with permission-style strings. If only `"IdentityOnly"`, `"BffOnly"`, or parameterless auth exists, removal is safe.

---

## Step 9: Add Tests

For each module with a provider, create `test/{Module}/Developer/PermissionMapping.{Specs,Steps}.cs`:

```csharp
// Specs
public partial class PermissionMappingSpecs : Specification
{
    [Fact]
    public async Task AllProviderPermissions_HaveMatchingConstants()
    {
        await GivenAsync(CollectPermissionsAndMappings);
        When(CheckingPermissionConstantsCoverage);
        Then(AllProviderPermissionValuesHaveMatchingConstants);
    }
}

// Steps
public partial class PermissionMappingSpecs
{
    private List<string> _permissionConstants = [];
    private List<string> _providerPermissionValues = [];
    private List<string> _unmappedProviderPermissions = [];

    private async Task CollectPermissionsAndMappings()
    {
        _permissionConstants = [ /* all Permissions.*.Key values */ ];

        {Module}RolePermissionProvider provider = new();
        var mappings = await provider.Get(CancellationToken.None);
        _providerPermissionValues = mappings.Values
            .SelectMany(permissions => permissions.Select(p => p.Key))
            .Distinct().ToList();
    }

    private void CheckingPermissionConstantsCoverage()
        => _unmappedProviderPermissions = _providerPermissionValues
            .Where(p => !_permissionConstants.Contains(p)).ToList();

    private void AllProviderPermissionValuesHaveMatchingConstants()
        => _unmappedProviderPermissions.Should().BeEmpty(
            "every permission in the provider should have a corresponding constant in Permissions");
}
```

When all role mappings are fully defined, add the reverse test (all constants appear in at least one role).

### Handler developer tests

Create `test/{Module}/Developer/UserRolesUpdated.{Specs,Steps}.cs` to verify the full pipeline: event consumption → role mapping → correct grants in SQL.

The SQL fixture needs a `GrantsDb` property and a `GetGrantsByUserId` helper. See ClientActions `test/Transfers/Collection.cs` for the pattern.

```csharp
// Specs
public partial class UserRolesUpdatedSpecs : Specification
{
    [Fact]
    public async Task Handle_WithValidEvent_WritesCorrectGrants()
    {
        Given(AValidUserRolesUpdatedEvent);
        await WhenAsync(HandlingTheEvent);
        await ThenAsync(CorrectGrantsAreInserted);
    }

    [Fact]
    public async Task Handle_WithUnknownRoleId_SkipsUnknownRole()
    {
        Given(AnEventWithUnknownRoleId);
        await WhenAsync(HandlingTheEvent);
        await ThenAsync(NoGrantsAreInserted);
    }

    [Fact]
    public async Task Handle_WithEmptyRoles_RevokesAllGrants()
    {
        await GivenAsync(ExistingGrantsForUser);
        Given(AnEventWithEmptyRoles);
        await WhenAsync(HandlingTheEvent);
        await ThenAsync(NoGrantsAreInserted);
    }
}

// Steps — construct handler directly with real providers and fixture GrantsDb
[Collection(Collection.Name)]
public partial class UserRolesUpdatedSpecs(
    {Module}SqlFixture sqlFixture) : IAsyncLifetime
{
    private UserRolesUpdatedEvent _event = null!;
    private readonly string _userId = Guid.NewGuid().ToString();

    private async Task HandlingTheEvent()
    {
        IRolePermissionProvider[] providers = [new {Module}RolePermissionProvider()];
        var options = MsOptions.Options.Create(new UserRolesGrantHandlerOptions { Enabled = true });
        UserRolesUpdatedEventHandler handler = new(providers, sqlFixture.GrantsDb, options, _logger);
        await handler.HandleAsync(_event);
    }

    private async Task CorrectGrantsAreInserted()
    {
        var grants = await sqlFixture.GetGrantsByUserId(_userId);
        grants.Should().BeEquivalentTo([ /* expected grants */ ]);
    }
}
```

These tests verify:
1. **Event consumption** — handler receives and processes the event without error
2. **Role mapping** — known roles produce the correct permissions, unknown roles are skipped
3. **Grant DB insert** — grants are atomically written to `[Shared].[Grants]` (and revoked when roles are empty)

---

## Known Monolith Variations

| Monolith | Grants Table | Timestamp | GrantId | Bespoke Handler | Notes |
|----------|-------------|-----------|---------|----------------|-------|
| ClientActions | `[Shared].[Grants]` | `CreatedAt` | Yes | Simple handler | Reference implementation |
| MoneyMovement | `[Shared].[RoleGrants]` | `CreateAt` (typo) | No | None | Greenfield adoption |
| Organisation | `[Shared].[RoleGrants]` | `CreatedAt` | No | 2-stage delta w/ `ApplyPermissionsDeltaCommand` | Also publishes `UserRolesUpdatedEvent` — keep publisher |
| ComplianceMonolith | `[Auth].[Grant]` | `CreatedAt` | Yes | None (SP sync) | Has `FallbackAuthorizationPolicyProvider` (dead — remove) |

---

## Checklist

- [ ] Audited: grants table, permissions, existing handlers, package versions
- [ ] User confirmed plan
- [ ] Freemarket.* packages >= 8.0.0
- [ ] Grants table migration: GrantId, column rename, type change, default constraint
- [ ] Shared RoleIds class created
- [ ] IRolePermissionProvider per module (static, SQL-backed, or placeholder)
- [ ] `AddUserRolesGrantHandler()` wired in DI
- [ ] Shared subscription added to `.AddApplication()`
- [ ] SDK handler assembly added to `.AddApplication()`
- [ ] `UserRolesRetryPipeline` registered in `CreateResiliencePipelineRegistry()`
- [ ] `UserRolesGrantHandler` config in appsettings.json
- [ ] Bespoke handler/event/mapper/mapping removed (publisher kept if applicable)
- [ ] `IPermissionProvider` and `FallbackAuthorizationPolicyProvider` removed
- [ ] Permission mapping BDD tests per module
- [ ] Build passes, 0 warnings, 0 errors
- [ ] No remaining references to deleted types
