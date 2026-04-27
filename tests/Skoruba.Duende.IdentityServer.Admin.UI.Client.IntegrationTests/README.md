# UI Integration Tests (Playwright)

This project contains end-to-end UI tests for the React admin client in `Skoruba.Duende.IdentityServer.Admin`.

## Scope

The suite covers:

1. Full authentication path (redirect to STS and back)
2. `Clients` list + seeded client detail
3. `Clients` create/edit/persistence flow
4. `ApiResources` list + seeded API resource detail
5. `ApiResources` create/edit/persistence flow

## Test Structure

- `tests/clients.spec.ts` - test orchestration only (short entrypoint)
- `tests/api-resources.spec.ts` - API resources test orchestration
- `tests/helpers/*` - reusable UI/auth/form helpers
- `tests/scenarios/client-persistence-flow.ts` - full create/update/reopen persistence scenario
- `tests/scenarios/api-resource-persistence-flow.ts` - API resource create/update/reopen persistence scenario

## Default Data Sources

The tests read credentials and expected resources from seed files:

- `src/Skoruba.Duende.IdentityServer.Admin.Api/identitydata.json`
- `src/Skoruba.Duende.IdentityServer.Admin.Api/identityserverdata.json`

It also supports alternative names (`identity.json`, `identityserver.json`) and env overrides.

## Prerequisites

Run these services before executing tests:

- `Skoruba.Duende.IdentityServer.STS.Identity`
- `Skoruba.Duende.IdentityServer.Admin.Api`
- `Skoruba.Duende.IdentityServer.Admin`

Default URLs expected by tests:

- Admin UI: `https://localhost:7127`
- STS: `https://localhost:44310`
- Admin API: `https://localhost:44302`

## Install

```bash
cd tests/Skoruba.Duende.IdentityServer.Admin.UI.Client.IntegrationTests
npm install
npx playwright install chromium
```

## Run

```bash
npm test
```

Headed mode:

```bash
npm run test:headed
```

## Environment Variables

- `E2E_ADMIN_URL` (default: `https://localhost:50445`)
- `E2E_STS_URL` (default: `https://localhost:44310`)
- `E2E_IDENTITY_JSON` (path to identity users JSON)
- `E2E_IDENTITYSERVER_JSON` (path to identityserver clients JSON)
- `E2E_USERNAME` (optional override)
- `E2E_PASSWORD` (optional override)
- `E2E_EXPECTED_CLIENT_ID` (optional override)
- `E2E_EXPECTED_API_RESOURCE_NAME` (optional override)
- `E2E_ADMIN_ROLE` (default: `SkorubaIdentityAdminAdministrator`)

## Reports

- HTML report: `playwright-report/index.html`
- Traces/videos/screenshots on failure: `test-results/`
