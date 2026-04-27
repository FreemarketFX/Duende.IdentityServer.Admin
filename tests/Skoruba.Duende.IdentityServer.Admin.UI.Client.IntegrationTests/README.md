# UI Integration Tests (Playwright)

This project contains end-to-end UI tests for the React admin client in `Skoruba.Duende.IdentityServer.Admin`.

## Scope

The default test covers the full authentication path:

1. Open protected Admin UI route (`/clients`)
2. Redirect to `/account/login` and then to STS
3. Sign in using credentials from identity seed JSON
4. Return to Admin UI and assert clients table is populated
5. Locate a seeded client by `clientId`
6. Open client detail page and validate loaded client

## Test Structure

- `tests/clients.spec.ts` - test orchestration only (short entrypoint)
- `tests/helpers/*` - reusable UI/auth/form helpers
- `tests/scenarios/client-persistence-flow.ts` - full create/update/reopen persistence scenario

## Default Data Sources

The test reads credentials and expected client from seed files:

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
- `E2E_ADMIN_ROLE` (default: `SkorubaIdentityAdminAdministrator`)

## Reports

- HTML report: `playwright-report/index.html`
- Traces/videos/screenshots on failure: `test-results/`
