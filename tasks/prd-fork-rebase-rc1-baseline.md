# PRD: FMFX fork rebase — Skoruba 3.0.0-rc1 baseline (Story 1)

## Introduction

The `FreemarketFX/Duende.IdentityServer.Admin` fork branched from upstream `skoruba/Duende.IdentityServer.Admin@release/1.2.0` in 2022 and never re-synced. Its `2.3.0-FMFX.N` package versions are a hand-rolled forward-port — they are not actually based on upstream 2.x. The fork is on .NET 8.

.NET 8 LTS support ends 2026-11-10. .NET 9 STS is already past end-of-support. The only viable target is .NET 10 LTS (supported until November 2028), which upstream Skoruba reached in its `release/3.0.0` line.

This story re-baselines the fork onto upstream `release/3.0.0-rc1` (the most actively-maintained 3.0.x branch). It is **scope-bounded to a clean baseline only** — porting our bespoke FMFX code (custom Dashboard, schema-from-appsettings, admin lockdowns, misc fixes) happens in later stories of the same epic.

## Goals

- A new long-lived branch (`feature/rebase-onto-3.0.0-rc1`) tracking upstream `release/3.0.0-rc1`.
- A clean `dotnet build` on .NET 10 SDK with no FMFX customisations applied.
- `Directory.Build.props` versioned `3.0.0-FMFX.1` so subsequent stories publish recognisably-FMFX packages.
- CodeQL workflow re-enabled and green.
- Publish workflow updated to target the FreemarketFX GitHub Packages NuGet feed from the new branch.
- README updated so anyone landing on the fork understands the new upstream baseline and re-base strategy.

## User Stories

### US-001: Bump fork version to 3.0.0-FMFX.1
**Description:** As a downstream consumer, I want fork-published packages to carry a `3.0.0-FMFX.1` version so I can identify them as Freemarket's rebase-baseline build, distinct from upstream `3.0.0-preview.N` and from the legacy `2.3.0-FMFX.N` line.

**Acceptance Criteria:**
- [ ] `Directory.Build.props` `<Version>` updated to `3.0.0-FMFX.1`.
- [ ] No other version-bearing files diverge from upstream `release/3.0.0-rc1` for this story.
- [ ] `dotnet build src/Skoruba.Duende.IdentityServer.Admin.sln --configuration Release` succeeds with no errors and no new warnings beyond upstream's baseline.
- [ ] Associated tests pass (run `dotnet test` against all `tests/*` projects — must match upstream rc1's green state).

### US-002: Verify clean upstream build on .NET 10 SDK
**Description:** As a developer, I want a documented, reproducible green build of upstream `release/3.0.0-rc1` from the new working tree so we have a known-good baseline before applying any FMFX changes.

**Acceptance Criteria:**
- [ ] `global.json` (if present) pins a .NET 10 SDK version; if absent, document the SDK version used in `README.md` setup instructions.
- [ ] `dotnet --version` reports a `10.0.x` SDK.
- [ ] `npm ci` and `npm run build:spa` succeed in `src/Skoruba.Duende.IdentityServer.Admin.UI.Client/` (produces `Admin.UI.Spa/wwwroot/` contents).
- [ ] `dotnet build src/Skoruba.Duende.IdentityServer.Admin.sln --configuration Release` succeeds.
- [ ] `dotnet test` against `tests/Skoruba.Duende.IdentityServer.Admin.UnitTests` and `tests/Skoruba.Duende.IdentityServer.Admin.IntegrationTests` and `tests/Skoruba.Duende.IdentityServer.STS.IntegrationTests` all pass.
- [ ] Build passes.
- [ ] Associated tests pass.

### US-003: Update publish workflow to target FreemarketFX GitHub Packages
**Description:** As a release engineer, I want the NuGet publish workflow on the new branch to push to the FreemarketFX GitHub Packages feed (not upstream's destination), so that subsequent stories can produce consumable `3.0.0-FMFX.N` packages.

**Acceptance Criteria:**
- [ ] Workflow file in `.github/workflows/` updated so that `dotnet pack` / `dotnet nuget push` targets the FreemarketFX GitHub Packages feed (`https://nuget.pkg.github.com/FreemarketFX/index.json`).
- [ ] Authentication uses the existing FreemarketFX GitHub Packages publish token convention (mirror how this was wired on the old `main` — see the previous fork's publish workflow for the secret name).
- [ ] Workflow triggers on push/release for `feature/rebase-onto-3.0.0-rc1` (and `main` once promoted).
- [ ] Workflow does NOT push from the upstream-tracking branches.
- [ ] Workflow lint / `act` (or visual inspection) confirms YAML validity.
- [ ] Build passes.
- [ ] Associated tests pass.

### US-004: Re-enable CodeQL workflow on the new branch
**Description:** As a security owner, I want CodeQL scanning enabled on the new branch from day one so security findings track from the baseline, not from when bespoke code lands.

**Acceptance Criteria:**
- [ ] CodeQL workflow file exists in `.github/workflows/` (port the configuration from the previous fork's `chore(FMFX-8682): Setup GitHub Advanced Security` commit if not present in upstream).
- [ ] Workflow triggers on push/PR for `feature/rebase-onto-3.0.0-rc1`.
- [ ] Languages configured for both `csharp` and `javascript-typescript` (covering the SPA).
- [ ] Visual inspection: CodeQL config valid; no obviously broken globs.
- [ ] Build passes.
- [ ] Associated tests pass.

### US-005: Update README with new baseline and re-base strategy
**Description:** As anyone landing on the repo, I want the README to make clear that this is now a fork of upstream `release/3.0.0-rc1`, that the long-lived branch has changed, and what the re-base plan is, so I don't act on stale assumptions from the old 1.2.0-based code.

**Acceptance Criteria:**
- [ ] README.md updated with a "Freemarket fork" section at the top noting:
  - Upstream baseline: `skoruba/Duende.IdentityServer.Admin@release/3.0.0-rc1`.
  - Active branch: `feature/rebase-onto-3.0.0-rc1` (will become `main` after the rebase epic completes).
  - Package versioning: `3.0.0-FMFX.N`.
  - Re-base plan: re-base onto stable `3.0.0` once Skoruba tags it.
  - Link to `CLAUDE.md` in this repo and to `Freemarket.Identity/CLEANUP-PLAN.md` for the epic-level plan.
- [ ] No deletion of upstream README content beyond what's needed to avoid contradiction.
- [ ] Build passes.
- [ ] Associated tests pass.

### US-006: Prepare branch for PR (not push, not merge)
**Description:** As the developer running this story, I want the branch in a clean, reviewable state with all commits clearly attributable, so the human reviewer can verify each step before pushing or opening a PR.

**Acceptance Criteria:**
- [ ] `git status` shows a clean working tree on `feature/rebase-onto-3.0.0-rc1`.
- [ ] `git log feature/rebase-onto-3.0.0-rc1 ^upstream/release/3.0.0-rc1 --oneline` shows only the commits added by US-001 through US-005 plus the setup commits (claude-shared subtree add + CLAUDE.md).
- [ ] Each commit message follows Conventional Commits (`feat:`, `chore:`, `docs:` etc.) and ends with the standard `Co-Authored-By: Claude (...)` trailer.
- [ ] No push to origin. No PR opened. Human reviews locally first.
- [ ] Build passes.
- [ ] Associated tests pass.

## Functional Requirements

- **FR-1:** The fork's solution (`src/Skoruba.Duende.IdentityServer.Admin.sln`) must build clean under .NET 10 SDK on the new branch.
- **FR-2:** `Directory.Build.props` `<Version>` must read `3.0.0-FMFX.1`.
- **FR-3:** The publish workflow in `.github/workflows/` must target the FreemarketFX GitHub Packages NuGet feed when running from this branch.
- **FR-4:** A CodeQL workflow must be present and configured for C# and TypeScript scanning on this branch.
- **FR-5:** The README must describe the new upstream baseline and re-base strategy.
- **FR-6:** No FMFX customisations from the old `main` (Dashboard, schema config, lockdowns, etc.) are introduced in this story.
- **FR-7:** The MySQL EF provider (removed upstream) must not be re-introduced.
- **FR-8:** AutoMapper (removed upstream in favour of Mapperly) must not be re-introduced.

## Non-Goals (Out of Scope)

- Porting the custom Dashboard feature, related EF view entities, services, repositories, controller, or React component (Story 2).
- Porting `IdentityTableConfiguration` / schema-from-appsettings (Story 3).
- Porting the misc fixes — client-ID generator, secret_-prefixed secrets, grant-type ordering, `UserLoginSuccessEvent` on 2FA login (Story 3).
- Implementing the FMFX-6240 / FMFX-6745 admin lockdowns (Story 4).
- Publishing actual `3.0.0-FMFX.1` packages end-to-end (Story 5 — this story only readies the workflow).
- Replacing or force-pushing the fork's existing `main` branch (a follow-up administrative action after the epic completes).
- Setting up Mapperly tooling beyond what upstream already provides (already in place since upstream 3.0).
- Bumping `Freemarket.Identity` to consume the new packages (Story 6).
- Periodic re-syncs with upstream `release/3.0.0-rc1` during the epic (decision: fetch once at branch creation, re-base after Skoruba tags stable `3.0.0`).

## Design Considerations

- The `claude-shared/` subtree is already in place on this branch (added during Story 1 setup, before this PRD was generated). Subsequent stories should leave it alone and update it via `claude-shared/update-claude-shared.ps1` when needed.
- The repo `CLAUDE.md` (also added during setup) is the source of truth for fork-specific conventions. Patterns described in `claude-shared/CLAUDE_TEMPLATE.md` are for the modular monolith and do **not** apply here.
- The publish workflow will be similar in shape to the one on the legacy `main` — reuse its secret name, action versions, and trigger pattern unless they're materially outdated.

## Technical Considerations

- **No CLAUDE.md from upstream.** Upstream Skoruba has no CLAUDE.md, so all architecture/conventions guidance comes from `CLAUDE.md` in this repo plus `claude-shared/`.
- **Architecture: layered DDD**, not the modular-monolith pattern documented in `claude-shared/CLAUDE_TEMPLATE.md`. Service → Repository → DbContext flow, Mapperly for DTO↔entity mapping, NSwag for OpenAPI + TS client generation. No Brighter, no Darker, no aggregates.
- **Persistence: EF Core 10**, SQL Server and PostgreSQL providers. Migrations per provider. Do not add MySQL (Pomelo not net10-compatible; upstream removed it).
- **No vertical slices**, no command/query handlers in the Brighter sense. Keep the existing controller/service/repository layout.
- **SPA build pipeline.** `Admin.UI.Client/.esproj` is the React/Vite source; `build-and-copy.js` copies the Vite output into `Admin.UI.Spa/wwwroot/`. The host ASP.NET project serves it as static files. Single deployable; no Azure Static Web Apps.
- **No new dependencies in this story.** The only changes are version bump, workflow wiring, README, and CodeQL config.
- **Branch tracking note.** The new branch was created with `git checkout -b feature/rebase-onto-3.0.0-rc1 upstream/release/3.0.0-rc1`, so it currently tracks `upstream`. When first pushed, set upstream to `origin/feature/rebase-onto-3.0.0-rc1` to avoid accidental pushes to skoruba.

## Testing Strategy

This story does **not** add new product code, so it doesn't introduce new tests. It verifies upstream's existing test suite still passes against our branch.

- **Run upstream's existing test suites:**
  - `dotnet test tests/Skoruba.Duende.IdentityServer.Admin.UnitTests`
  - `dotnet test tests/Skoruba.Duende.IdentityServer.Admin.IntegrationTests`
  - `dotnet test tests/Skoruba.Duende.IdentityServer.STS.IntegrationTests`
  - Plus any other test projects upstream `release/3.0.0-rc1` ships.
- **Expected state:** matches upstream rc1's green state. Any failure here is a setup problem (SDK version, npm dependencies, container availability), not a regression.
- **No new fakes/spies needed.** Test doubles are introduced in later stories (e.g. Story 4's lockdown tests, Story 2's Dashboard tests).
- **BDD/Brighter testing patterns** documented in `claude-shared/CLAUDE_TEMPLATE.md` do **not** apply here — this repo uses xUnit + the upstream test patterns.

## Success Metrics

- Solution builds clean on .NET 10 in CI.
- All upstream test suites green on the new branch.
- Publish workflow passes a YAML lint and is configured to push to FreemarketFX GitHub Packages.
- CodeQL workflow runs and reports no new findings beyond upstream baseline.
- Branch is in a state where the next PR (Story 2: Dashboard port) can start cleanly from it.

## Open Questions

- **CodeQL config:** Should we mirror the old fork's `FMFX-8682` CodeQL setup verbatim, or use GitHub's "default setup" for CodeQL on the new branch? Default setup is lower-maintenance; verbatim is closer to what audit/security previously approved.
- **Publish secret name:** Confirm with whoever currently maintains FreemarketFX GitHub Packages secrets that the existing publish token still works for the new branch — otherwise this story needs an extra step to issue a fresh token.
- **README content rewrite scope:** Should we keep upstream's full README (which describes Skoruba's project) plus a Freemarket prefix, or rewrite the README to be Freemarket-focused with a link out to upstream? Lighter touch is the prefix; cleaner is the rewrite. Recommend prefix-only for this story, defer larger rewrite.
