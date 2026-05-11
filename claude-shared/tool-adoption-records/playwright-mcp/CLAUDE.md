# Playwright MCP — Adoption-Record Determinism Contract

## Identity
- **Slug:** `playwright-mcp`
- **Tool name:** Playwright MCP
- **Endpoint / version:** `mcr.microsoft.com/playwright/mcp:v0.0.75@sha256:d238ec7bc98cc4e22df0696d6031dad5b8a4b46781f4f0abaa3bfadeedb43b9a` (HTTP on `http://localhost:8931/mcp`)
- **Vendor:** Microsoft (`github.com/microsoft`)

## Sources consulted
- `https://github.com/microsoft/playwright-mcp` — README, declared MCP tools, capability flags, transports — fetched 08 May 2026.
- `https://github.com/microsoft/playwright-mcp/blob/main/SECURITY.md` — vendor disclosure process — fetched 08 May 2026.
- `https://github.com/microsoft/playwright-mcp/security/advisories` — published advisories (none) — fetched 08 May 2026.
- `https://hub.docker.com/r/microsoft/playwright-mcp` — publisher metadata — fetched 08 May 2026 (note: canonical image lives on MCR, Docker Hub mirror has limited metadata).
- `C:\dev\git\claude-shared\ralph-sandbox\mcp\playwright\README.md` — FMFX deployment description — read 08 May 2026.
- `C:\dev\git\claude-shared\ralph-sandbox\mcp\playwright\compose.yml` — base compose definition — read 08 May 2026.
- `C:\dev\git\claude-shared\ralph-sandbox\mcp\playwright\compose-sandbox.yml` — sandbox proxy overrides — read 08 May 2026.
- `C:\dev\git\claude-shared\ralph-sandbox\mcp\playwright\compose-sandbox-startup.sh` — proxy CA cert injection script — read 08 May 2026.
- `docker buildx imagetools inspect mcr.microsoft.com/playwright/mcp:v0.0.75` — multi-arch OCI index digest + BuildKit attestation manifests — run 08 May 2026.

## Tool enumeration source
Authoritative list: `https://github.com/microsoft/playwright-mcp` README "Tools" section. The default `--caps=core` set is the canonical adoption surface; opt-in capability buckets (`vision`, `pdf`, `devtools`, `network`, `storage`, `testing`) are out of scope unless the deployment compose passes `--caps=...`. Re-runs MUST consult the same README section against the pinned image's documentation.

## Classification rationale
- **`data_classes`: `internal`, `confidential`** — `playwright.allowedDomains` defaults to `*.wearefreemarket.com`, which can resolve to FMFX-internal admin / portal surfaces. Public-only is too narrow because the in-scope use case is testing FMFX apps; Restricted is excluded because PII / payments flows are not the documented use case.
- **`is_section_3_2_source`: false** — Playwright MCP is generic browser automation, not itself a SharePoint / Slack / Jira / Confluence / Outlook / Teams integration. The §3.2 risk flips to true only if `allowedDomains` is widened to include those surfaces — captured as a re-review trigger.
- **`risk_level`: medium** — Microsoft-published, MCR-distributed, Apache-2.0, very active release cadence (65 releases at the time of review), no published advisories. The capability surface (in-page JS, arbitrary Playwright code, network egress to navigated pages) is broad, but mitigated by `--isolated`, allowed-origins, the loopback bind, the sandbox proxy choke point, and the managed-settings deny of the two code-execution tools. Not Low because the indirect-injection path through `browser_navigate` → read-tools is intrinsic.
- **`tier`: elevated** — introduces mutating browser actions, in-browser code-execution tools (denied but architecturally present), and HTTP transport (loopback-bound). FMFX policy escalates these to Elevated regardless of the loopback constraint.

## Allow / deny derivation
**Rule:** Allow every `core` tool except those that map to "execute model-supplied code". Deny `browser_evaluate` (page-level JS execution) and `browser_run_code_unsafe` (vendor-labelled-unsafe Playwright API). All other mutating tools (`browser_click`, `browser_type`, `browser_navigate`, `browser_fill_form`, etc.) are allowed because they are necessary for the core test-automation use case and their effect is bounded by the in-page accessibility surface.

If a future re-run adds opt-in capability buckets, apply the same rule recursively: deny anything whose effect is "run a script" or "mock the network" (`browser_route_*`, `browser_network_state_set`) until justified; allow read-shaped verbs (`browser_get_*`, `browser_*_list`).

## MCP server name
`playwright` — matches the `servers.playwright` key in `tasks/config/mcp-servers.yml` (per `ralph-sandbox/mcp/playwright/README.md`). Permission strings therefore have the shape `mcp__playwright__<tool>`. Locked here so re-runs do not drift to `mcp__playwright-mcp__*`.

## Reviewer feedback log

### 08 May 2026 — round 1
- **Feedback (verbatim):** "slug should be \"playwright\"" → then "change slug to playwright-mcp"
- **Decision:** Reverted from the auto-derived `playwright-mcp` to `playwright` mid-review per first instruction, then restored to `playwright-mcp` per second instruction. MCP server name (the value in the `mcp__<server>__<tool>` permission shape) stays `playwright` because that is the key used by `tasks/config/mcp-servers.yml` per `ralph-sandbox/mcp/playwright/README.md` — `settings.json` is unaffected.
- **Files updated:** `snapshot.json`, `adoption-record.md`, `CLAUDE.md`; directory renamed `playwright-mcp` → `playwright` → `playwright-mcp`. `settings.json` unchanged.

### 08 May 2026 — round 2
- **Feedback (verbatim):** "before we continue, update image in compose.yml with digest-pin for v0.0.75 and reflect this in the current md/snapshot"
- **Decision:** Resolved the multi-arch OCI index digest via `docker buildx imagetools inspect` → `sha256:d238ec7bc98cc4e22df0696d6031dad5b8a4b46781f4f0abaa3bfadeedb43b9a`. Updated the deployed `compose.yml` to `image: mcr.microsoft.com/playwright/mcp:v0.0.75@sha256:d238ec7…`. In the snapshot: `version_or_path` now includes the digest, `supply_chain.pinned_by_hash` flipped `false` → `true`, and `supply_chain.signed_release` flipped `false` → `true` because the image carries Docker BuildKit attestation manifests (SLSA provenance + SBOM) for both `linux/amd64` and `linux/arm64`. `sigstore` stays `false` (no Sigstore / cosign identity verification was performed). The digest-pin condition under "Conditions / scope limits" was rewritten from "upgrade at next review" to "must stay digest-pinned; bumps require re-review".
- **Files updated:** `ralph-sandbox/mcp/playwright/compose.yml`, `tool-adoption-records/playwright-mcp/snapshot.json`, `tool-adoption-records/playwright-mcp/adoption-record.md`, `tool-adoption-records/playwright-mcp/CLAUDE.md`. `settings.json` unchanged.

### 08 May 2026 — round 4
- **Feedback (verbatim):** "update status with Approved-with-conditions in bold"
- **Decision:** Set the header Status line in `adoption-record.md` from `**Proposed**` to `**Approved-with-conditions**`, matching the Decision § Outcome. Per skill rules, `Approved*` is now the binding decision and MUST be replicated verbatim on any re-run.
- **Files updated:** `tool-adoption-records/playwright-mcp/adoption-record.md`, `tool-adoption-records/playwright-mcp/CLAUDE.md`. `snapshot.json` and `settings.json` unchanged.

### 08 May 2026 — round 3
- **Feedback (verbatim):** "distribution - pick out relevant details from C:\\dev\\git\\claude-shared\\ralph-sandbox\\mcp\\playwright\\README.md" → then "for the sandbox distribution, lets add a code block with an example configuration. we can also add a hyperlink to the readme as a reference at the top of the distribution section?"
- **Decision:** Populated the Decision § Distribution bullet using the README's "Setup" + "Adding allowed domains" sections as the source-of-truth: link to the README at the top, then prose covering the three Compose files, three activation paths (Ralph sandbox / local-dev `mcp-startup.ps1` / egress allow-list central config), plus a fenced YAML code block for the `tasks/config/mcp-servers.yml` entry and a second YAML block for the `playwright.allowedDomains` shape. Settings-distribution caveat retained at the end.
- **Files updated:** `tool-adoption-records/playwright-mcp/adoption-record.md`, `tool-adoption-records/playwright-mcp/CLAUDE.md`. `snapshot.json` and `settings.json` unchanged.

## Determinism contract
On re-run with unchanged upstream data, the following decisions MUST reproduce verbatim:

- **`slug`:** `playwright-mcp` (matches the `<tool>-mcp` convention used by sibling adoption records, e.g. `datadog-mcp`).
- **MCP server name:** `playwright` — used to construct `mcp__playwright__*` permission strings.
- **`risk_level`:** `medium`
- **`tier`:** `elevated`
- **`is_section_3_2_source`:** `false`
- **`data_classes`:** `internal`, `confidential` (in this order in the snapshot's deduped array)
- **Allow/deny rule:** deny `browser_evaluate` + `browser_run_code_unsafe`; allow all other `core` tools.
- **Tool enumeration scope:** `core` capability bucket only — opt-in buckets are out of scope until the deployment compose passes `--caps=...`.

The only fields permitted to change without an upstream change are `reviewed_on` and `review_due` (the calendar advances).
