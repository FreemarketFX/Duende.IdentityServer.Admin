---
name: infrastructure-update
description: "Update bootstrap, bicep, and permissions when infrastructure changes. Use after adding a new Cosmos container, SQL schema, or permission scheme. Triggers on: update bootstrap, update bicep, update infrastructure, add container, add permissions, new scheme."
license: MIT
---

# Infrastructure Update

Update bootstrap, bicep, and permission registration when infrastructure has changed (e.g., new Cosmos container, new module, new permission scheme).

---

## The Job

1. Determine what infrastructure changed
2. Update bootstrap.cs (local Cosmos containers)
3. Update main.bicep (Azure infrastructure)
4. Update permission registration (if new scheme added)
5. Update SqlPermissions.json (if new SQL role needed)
6. Verify build passes

**Important:** Follow existing patterns in the codebase exactly. Each file has a consistent pattern — find the last entry and replicate it.

---

## Step 1: Determine What Changed

Ask the user (if not already clear from context):
- What was added? (new Cosmos container, new module, new permission scheme, new SQL schema)
- Module name (which bounded context)
- Container/resource name(s)

---

## Step 2: Update Bootstrap (Local Cosmos Containers)

**File:** `bootstrap.cs` (repo root)

If a **new Cosmos container** was added, add it to the `AdditionalContainers` dictionary:

```csharp
AdditionalContainers = new Dictionary<string, string> {
    { "balances", "partitionKey" },
    { "exchanges", "partitionKey" },
    // ... existing containers ...
    { "newcontainer", "partitionKey" },  // <-- Add here
},
```

**Partition key:** Domain containers that use durable domain events must use `"partitionKey"` to support transactional batches. Only non-domain containers (e.g. `http-request-audit`) may use `"id"`.

---

## Step 3: Update Bicep (Azure Infrastructure)

**File:** `infrastructure/main.bicep`

### New Cosmos Container

Add a new module block following the existing pattern:

```bicep
module {name}CosmosContainer 'br/fmfxbicepmodulesregistry:cosmos-container:v1.3' = {
  name: '${deploymentPrefix}-{name}'
  params: {
    containerName: '{name}'
    accountName: cosmosAccountName
    databaseName: cosmosDatabase.outputs.name
    partitionKeyPaths: ['/partitionKey']
    tags: localTags
    useServerless: useServerless
    useContainerProvisioning: false
  }
}
```

**Placement:** Add after the last existing `cosmos-container` module block, before infrastructure containers (lease, inbox, outbox, healthcheck).

### New Role Assignment Module

If a new Azure resource type needs role assignments, add a roles module:

```bicep
module {name}Roles 'br/fmfxbicepmodulesregistry:{resource}-roles:v1.0' = {
  name: '${deploymentPrefix}-{name}-roles'
  params: {
    principalIds: [
      managedIdentity.outputs.managedIdentityPrincipalId
    ]
    {resourceName}: {resourceParamValue}
  }
}
```

---

## Step 4: Update Permissions (If New Scheme Added)

When a new module or permission scheme is added, update **all four** of these locations:

### 4a. Create Permission Definitions

**File:** `src/{Module}/Application/Auth/Permissions.cs`

```csharp
namespace {Module}.Auth;

public static class Permissions
{
    public static Permission {Resource}View => new("{Module}.{Resource}.View", "{Resource} View", "View {resource} details");
    public static Permission {Resource}Write => new("{Module}.{Resource}.Write", "{Resource} Write", "Create or update {resource}");
}
```

### 4b. Create Permission Provider in HostApp

**File:** `src/HostApp/Auth/{Module}PermissionProvider.cs`

```csharp
using Freemarket.PermissionAuth;

namespace {MonolithName}.HostApp.Auth;  // match the HostApp's actual root namespace

internal class {Module}PermissionProvider : IPermissionProvider
{
    public Permission? GetPermission(string policyName)
    {
        var permissionProperties = typeof({Module}.Auth.Permissions).GetProperties();

        return permissionProperties.SingleOrDefault(x => x.Name == policyName)?
            .GetValue(null) as Permission;
    }
}
```

### 4c. Register Permission Provider

**File:** `src/HostApp/Auth/ServiceCollectionExtensions.cs`

Add the extension method and call it in the chain. The existing `.Use*Permissions()` calls vary per monolith — read the current file first and append to the existing chain:

```csharp
// Add to the AddPermission method chain (existing calls shown as <existing>):
services.AddPermissionAuth()
    // <existing .Use*Permissions() calls — leave in place>
    .Use{Module}Permissions()          // <-- Add here
    .UseGrantsFromSqlServer(...);

// Add new private method:
private static PermissionAuthBuilder Use{Module}Permissions(this PermissionAuthBuilder permissionAuthBuilder)
{
    permissionAuthBuilder.Services.AddSingleton<IPermissionProvider, {Module}PermissionProvider>();
    return permissionAuthBuilder;
}
```

### 4d. Update SqlPermissions.json (If New SQL Role Needed)

**File:** `infrastructure/SqlPermissions.json`

Add the new role to the managed identity user:

```json
"fmfx-#{Instance}-#{Environment}-clientactions-id": {
  "type": "ExternalProvider",
  "roles": [
    "AccountBalancesService",
    "ExchangesService",
    "TransfersService",
    "{Module}Service"
  ]
}
```

Also create a SQL migration script for the new role:

**File:** `src/Shared/Migrations/Scripts/NNNN-Add{Module}ServiceRoles.sql`

---

## Step 5: Update Host Registration (If New Module)

If this is a completely new module, also update these files:

### HostBuilderExtensions.cs

**File:** `src/HostApp/HostBuilderExtensions.cs`

```csharp
// Add to .AddApplication() subscriptions array:
tnp => [..., {Module}BrighterExtensions.CreateSubscriptions(tnp)],

// Add to .AddApplication() publications array:
tnp => [..., {Module}BrighterExtensions.CreatePublications(tnp)],

// Add to assemblies array:
[..., Assembly.GetAssembly(typeof({Module}.Endpoints))!],

// Add to resilience registry:
.Add{Module}ResiliencePipeline(logger, config);

// Add module services:
.Add{Module}Services(context.Configuration);
```

### WebApplicationExtensions.cs

**File:** `src/HostApp/WebApplicationExtensions.cs`

```csharp
app
    .AddAccountBalanceEndpoints()
    .AddTransfersEndpoints()
    .AddExchangesEndpoints()
    .Add{Module}Endpoints();           // <-- Add here
```

---

## Step 6: Update bootstrap.ps1 (If New SQL Migration Project)

**File:** `bootstrap.ps1`

If a new module has its own migration project, add it to the migrations section:

```powershell
Write-Host "{Module} Migrations"
dotnet run `
    --project .\src\{Module}\Migrations\Migrations.csproj `
    --connectionString $sqlConnectionString
```

If a new test project exists, add test settings generation:

```powershell
Write-Host "-> {Module}.Tests appsettings.test.local.json"
Write-JsonFile $localOverride ".\test\{Module}\appsettings.test.local.json"
```

---

## Step 7: Verify

```bash
dotnet build --configuration Release /p:NetCoreBuild=true
```

Fix any build errors before completing.

---

## Checklist

- [ ] `bootstrap.cs` — new container added to `AdditionalContainers` (if Cosmos)
- [ ] `infrastructure/main.bicep` — new container/resource module added (if Cosmos/Azure)
- [ ] `infrastructure/main.bicep` — role assignment module added (if new resource type)
- [ ] `infrastructure/SqlPermissions.json` — new SQL role added (if new module)
- [ ] `src/{Module}/Application/Auth/Permissions.cs` — permission definitions created (if new scheme)
- [ ] `src/HostApp/Auth/{Module}PermissionProvider.cs` — provider created (if new scheme)
- [ ] `src/HostApp/Auth/ServiceCollectionExtensions.cs` — `.Use{Module}Permissions()` added (if new scheme)
- [ ] `src/HostApp/HostBuilderExtensions.cs` — module registered (if new module)
- [ ] `src/HostApp/WebApplicationExtensions.cs` — endpoints registered (if new module)
- [ ] `bootstrap.ps1` — migrations/test settings added (if applicable)
- [ ] Build passes
