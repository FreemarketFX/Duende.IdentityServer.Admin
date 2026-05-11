# CLAUDE.md — FreemarketFX/Duende.IdentityServer.Admin

## What this repo is

A Freemarket fork of [skoruba/Duende.IdentityServer.Admin](https://github.com/skoruba/Duende.IdentityServer.Admin). It publishes NuGet packages (`Skoruba.Duende.IdentityServer.Admin.*`) to the FreemarketFX GitHub Packages feed, which are consumed by `Freemarket.Identity`.

The fork is currently being **rebased onto upstream `release/3.0.0-rc1`**. The active baseline branch is `feature/rebase-onto-3.0.0-rc1`; once Story 5 of the rebase epic completes, that branch replaces `main`. After Skoruba tags stable `3.0.0`, we re-base again.

History note: the old `main` was a hand-rolled forward-port from upstream `release/1.2.0`. Do not treat it as authoritative — anything from old `main` only comes across via the rebase epic's explicit story tickets.

## Tech stack

- **.NET 10** (LTS). Target framework `net10.0` across all projects.
- **Duende IdentityServer 7.4.x**.
- **EF Core 10** with SQL Server and PostgreSQL providers. **MySQL was dropped upstream** in 3.0 (Pomelo not net10-compatible); don't add it back.
- **Mapperly** (source-generated mappers). Upstream replaced AutoMapper in 3.0 — do not introduce AutoMapper.
- **NSwag** (`14.7.x`) for OpenAPI + TypeScript client generation. The Admin.UI.Client TS client is regenerated on build via the `NSwag` MSBuild target in `Admin.UI.Api.csproj`.
- **React 18 + Vite + Tailwind + Radix UI + TanStack Query** for the SPA (`src/Skoruba.Duende.IdentityServer.Admin.UI.Client/`).
- **Serilog 10** for logging.

## Architecture (layered DDD)

This is **not** a modular monolith. Don't apply patterns from `claude-shared/CLAUDE_TEMPLATE.md` that assume Brighter/Darker, vertical slices, or aggregate roots — they don't fit here. The layout is classic Skoruba layered DDD:

```
src/
  Skoruba.Duende.IdentityServer.Admin/             # ASP.NET Core host (Admin UI shell)
  Skoruba.Duende.IdentityServer.Admin.UI/          # Razor views, controllers, host glue
  Skoruba.Duende.IdentityServer.Admin.UI.Api/      # JSON API consumed by the React SPA
  Skoruba.Duende.IdentityServer.Admin.UI.Spa/      # Static wwwroot (built SPA bundle lives here)
  Skoruba.Duende.IdentityServer.Admin.UI.Client/   # React/Vite source (.esproj)
  Skoruba.Duende.IdentityServer.Admin.Api/         # Standalone JSON API host
  Skoruba.Duende.IdentityServer.Admin.BusinessLogic/         # Services + DTOs (configuration store)
  Skoruba.Duende.IdentityServer.Admin.BusinessLogic.Identity/# Services + DTOs (identity store)
  Skoruba.Duende.IdentityServer.Admin.BusinessLogic.Shared/  # Shared service helpers
  Skoruba.Duende.IdentityServer.Admin.EntityFramework/                 # Repositories + interfaces
  Skoruba.Duende.IdentityServer.Admin.EntityFramework.Identity/        # Identity repositories
  Skoruba.Duende.IdentityServer.Admin.EntityFramework.Shared/          # DbContexts
  Skoruba.Duende.IdentityServer.Admin.EntityFramework.Configuration/   # Connection/config helpers
  Skoruba.Duende.IdentityServer.Admin.EntityFramework.SqlServer/       # SQL Server provider + migrations
  Skoruba.Duende.IdentityServer.Admin.EntityFramework.PostgreSQL/      # PostgreSQL provider + migrations
  Skoruba.Duende.IdentityServer.Admin.EntityFramework.Admin/           # Admin schema entities
  Skoruba.Duende.IdentityServer.Admin.EntityFramework.Admin.Storage/   # Admin schema storage
  Skoruba.Duende.IdentityServer.Admin.EntityFramework.Extensions/      # DI/builder extensions
  Skoruba.Duende.IdentityServer.STS.Identity/      # The STS host (login/registration)
  Skoruba.Duende.IdentityServer.Shared/            # Cross-cutting types
  Skoruba.Duende.IdentityServer.Shared.Configuration/  # Auth/role/registration config
```

Flow: **Controller → Service → Repository → EF Core → DbContext**. Mapperly mappers between DTOs and entities live alongside the service that uses them.

The React SPA (`Admin.UI.Client`) is hosted in-process: Vite builds to `dist/`, the `build:spa` npm script copies to `Admin.UI.Spa/wwwroot/`, and ASP.NET Core static-file middleware serves it. **Deployment stays as a single ASP.NET Core artifact** — do not introduce Azure Static Web Apps or a split frontend deploy.

## Conventions to follow

- **Read before writing.** Before modifying any file, read it. Before introducing a pattern (a new service, repository, controller, mapper), find an existing example in the same project and mirror it.
- **No AutoMapper.** Upstream 3.0 deleted it. If you need a new mapping, write a Mapperly partial class (look at `src/Skoruba.Duende.IdentityServer.Admin.BusinessLogic/Mappers/` for examples).
- **No MySQL.** It was removed deliberately. Do not add `Pomelo.EntityFrameworkCore.MySql` or re-introduce the `EntityFramework.MySql` project.
- **Migrations.** EF migrations are per provider (`EntityFramework.SqlServer/Migrations/`, `EntityFramework.PostgreSQL/Migrations/`). Always generate for both providers when changing the model.
- **NSwag client.** When changing API contracts in `Admin.UI.Api`, the TS client regenerates on build. Don't hand-edit the generated client in the SPA.
- **NWebsec / security headers.** Don't loosen the security middleware in `STS.Identity` without a documented reason.
- **Don't sync with upstream ad-hoc.** Upstream syncs happen at story boundaries in the rebase epic, not in passing.

## Build & test

```powershell
# Build everything
dotnet build src/Skoruba.Duende.IdentityServer.Admin.sln --configuration Release

# Run admin host (.NET side)
dotnet run --project src/Skoruba.Duende.IdentityServer.Admin

# Build the SPA bundle into Admin.UI.Spa/wwwroot
cd src/Skoruba.Duende.IdentityServer.Admin.UI.Client
npm ci
npm run build:spa

# Tests
dotnet test tests/Skoruba.Duende.IdentityServer.Admin.UnitTests
dotnet test tests/Skoruba.Duende.IdentityServer.Admin.IntegrationTests
dotnet test tests/Skoruba.Duende.IdentityServer.STS.IntegrationTests
```

## Packaging & publish

- Versioning lives in `Directory.Build.props` (`<Version>`).
- FMFX versions are tagged `3.0.0-FMFX.N` (rolling pre-release of upstream 3.0).
- Packages publish to GitHub Packages under `FreemarketFX/Duende.IdentityServer.Admin` via the workflow in `.github/workflows/`.
- Consumed by `Freemarket.Identity` via the `nuget-github` registry in its `dependabot.yml`.

## Skills

The `claude-shared/` subtree provides shared skills, hooks and scripts. The skills it ships are pitched at the modular monolith — most don't apply here. The ones that **do** apply:

- `sync-claude-md` — diff this CLAUDE.md against `claude-shared/CLAUDE_TEMPLATE.md` (mostly to pick up template improvements that *also* apply here).
- `pr-feedback`, `pr-build-doctor` — repo-agnostic.
- `ralph`, `post-ralph`, `unarchive-prd` — Ralph workflow, used by stories in this repo (PRDs live in `tasks/`).

To update the subtree: `claude-shared/update-claude-shared.ps1`.

## Active work

See `tasks/` for in-flight PRDs. Top-level epic and full plan live in `Freemarket.Identity/CLEANUP-PLAN.md` (the consuming app's repo).
