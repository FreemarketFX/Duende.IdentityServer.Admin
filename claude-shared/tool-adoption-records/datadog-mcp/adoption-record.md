# Adoption Record — Datadog MCP Server (EU)

> Status: **Approved-with-conditions** (See [Decision](#Decision))
> Snapshot: `https://github.com/FreemarketFX/claude-shared/tool-adoption-records/datadog-mcp/snapshot.json`
> Reviewed: `06 May 2026` by `Rob Taylor` — Review due: `13 Aug 2026`
> Owner: **InfoSec and Platform Team**

## Decision
- **Outcome:** Approved-with-conditions
- **Conditions / scope limits:**
  - EU endpoint only (`mcp.datadoghq.eu`); US/AP endpoints not in scope.
  - Two permitted auth modes: (a) local interactive users via OAuth 2.0 (personal identity binding); (b) Docker sandbox environments via `DD_API_KEY` + `DD_APPLICATION_KEY` injected at container start from **Keeper Secrets Manager** — the application key MUST be bound to a read-only custom Datadog role. No other credential paths permitted (no .env files, no checked-in keys, no per-engineer API keys).
  - Datadog tenant role for BOTH engineer OAuth users AND the sandbox service principal must grant `mcp_read` and NOT `mcp_write`. The Datadog Standard Role (which grants both) is not used.
  - Re-snapshot before any plugin allowlist change.
- **Distribution:**
  - **Server registration:** Declared in `.mcp.json` inside the `freemarket-claude-skills` plugin. The MCP server is auto-loaded into every Claude Code session that has the plugin enabled — engineers do not register it manually.
  - **Authentication (per engineer, one-time):** run `/plugin`, navigate to the `Datadog MCP Server` entry under `freemarket-claude-skills`, and select `Authenticate` to complete the Datadog OAuth flow.
  - **Permissions:** the allow / deny patterns in this record are shipped as managed settings (`settings.json`) and govern which Datadog MCP tools Claude Code may invoke. Engineers cannot override the deny list locally.
  - **Sandbox usage:** for running the Datadog MCP server inside Ralph / Docker sandbox environments (KSM-injected `DD_API_KEY` + `DD_APPLICATION_KEY`, no per-engineer OAuth), follow the setup instructions at https://github.com/FreemarketFX/claude-shared/blob/main/ralph-sandbox/mcp/datadog/README.md.
- **Allowlist:**
  ```
  mcp__plugin_freemarket-claude-skills_datadog__*
  ```
  Rule: Claude Code permission patterns only support a single trailing `*` (entire tool-name segment), not infix or partial-name wildcards. A namespace-wide allow covers every Datadog MCP tool, and the deny list below enumerates every mutating tool by full name to ensure each deny entry actually matches at runtime.
- **Denylist:**
  ```
  mcp__plugin_freemarket-claude-skills_datadog__add_comment_to_datadog_case
  mcp__plugin_freemarket-claude-skills_datadog__append_reference_table_rows
  mcp__plugin_freemarket-claude-skills_datadog__browser_onboarding
  mcp__plugin_freemarket-claude-skills_datadog__create_datadog_case
  mcp__plugin_freemarket-claude-skills_datadog__create_datadog_feature_flag
  mcp__plugin_freemarket-claude-skills_datadog__create_datadog_monitor
  mcp__plugin_freemarket-claude-skills_datadog__create_datadog_notebook
  mcp__plugin_freemarket-claude-skills_datadog__create_reference_table
  mcp__plugin_freemarket-claude-skills_datadog__delete_datadog_dashboard
  mcp__plugin_freemarket-claude-skills_datadog__devices_onboarding
  mcp__plugin_freemarket-claude-skills_datadog__edit_datadog_notebook
  mcp__plugin_freemarket-claude-skills_datadog__edit_synthetics_tests
  mcp__plugin_freemarket-claude-skills_datadog__execute_datadog_workflow
  mcp__plugin_freemarket-claude-skills_datadog__kubernetes_onboarding
  mcp__plugin_freemarket-claude-skills_datadog__link_jira_issue_to_datadog_case
  mcp__plugin_freemarket-claude-skills_datadog__llm_observability_onboarding
  mcp__plugin_freemarket-claude-skills_datadog__serverless_onboarding
  mcp__plugin_freemarket-claude-skills_datadog__source_map_uploads
  mcp__plugin_freemarket-claude-skills_datadog__sync_datadog_feature_flag_allocations
  mcp__plugin_freemarket-claude-skills_datadog__synthetics_test_wizard
  mcp__plugin_freemarket-claude-skills_datadog__test_optimization_onboarding
  mcp__plugin_freemarket-claude-skills_datadog__update_datadog_case
  mcp__plugin_freemarket-claude-skills_datadog__update_datadog_feature_flag_environment
  mcp__plugin_freemarket-claude-skills_datadog__update_datadog_workflow_with_agent_trigger
  mcp__plugin_freemarket-claude-skills_datadog__upsert_datadog_dashboard
  ```
  Rule: enumerate every tool with `mutates: true` in `snapshot.json` by full name. Includes `synthetics_test_wizard` (read-shaped name, mutating effect) and all agentic onboarding tools. Re-derive this list on every snapshot diff — any new mutating tool must be added before approval extends to a new snapshot.
- **Token scope:** `mcp_read` only at the Datadog tenant; `mcp_write` revoked from the user's role.
- **Sandbox required:** No (remote SaaS, no local execution path)

## Identity
- **Name:** Datadog MCP Server (EU)
- **Slug:** datadog-mcp (EU endpoint; not region-qualified in slug since FMFX uses one region)
- **Type:** MCP Server
- **Source:** https://docs.datadoghq.com/bits_ai/mcp_server/
- **Version / endpoint path:** `https://mcp.datadoghq.eu/api/unstable/mcp-server/mcp`
- **Vendor / maintainer:** Datadog, Inc. (official vendor, vendor-hosted)
- **License:** Proprietary-SaaS

## Surface
- **Transport:** HTTPS (streamable HTTP MCP transport)
- **Auth (two modes):**
  - Local interactive users: OAuth 2.0 (per-user, personal identity binding) — scopes `mcp_read`, `mcp_write`.
  - Docker sandbox environments: `DD_API_KEY` + `DD_APPLICATION_KEY` injected at container start by **Keeper Secrets Manager (KSM)**; the underlying Datadog application key is bound to a service principal scoped to a read-only custom Datadog role.
- **Network egress:** `mcp.datadoghq.eu`
- **Dependencies (notable):** None — vendor-hosted remote service
- **Tool count:** 123 enumerated (99 read-only, 24 mutating). Datadog docs page now reports 123 — prior 121-vs-139 gap closed.
- **Mutating tools:**
  - `add_comment_to_datadog_case` — adds comment to case timeline
  - `append_reference_table_rows` — appends rows to reference table
  - `browser_onboarding` — agentic onboarding execution
  - `create_datadog_case` — creates Case Management case
  - `create_datadog_feature_flag` — creates feature flag
  - `create_datadog_monitor` — creates monitor (draft)
  - `create_datadog_notebook` — creates notebook
  - `create_reference_table` — creates reference table from cloud storage
  - `delete_datadog_dashboard` — permanently deletes dashboard
  - `devices_onboarding` — agentic onboarding execution
  - `edit_datadog_notebook` — edits existing notebook
  - `edit_synthetics_tests` — edits synthetic HTTP API tests
  - `execute_datadog_workflow` — executes workflow with agent trigger
  - `kubernetes_onboarding` — agentic onboarding execution
  - `link_jira_issue_to_datadog_case` — links Jira to case
  - `llm_observability_onboarding` — agentic onboarding execution
  - `serverless_onboarding` — agentic onboarding execution
  - `source_map_uploads` — agentic RUM source-map upload
  - `sync_datadog_feature_flag_allocations` — syncs flag allocations
  - `synthetics_test_wizard` — creates synthetic tests
  - `test_optimization_onboarding` — agentic onboarding execution
  - `update_datadog_case` — updates case fields
  - `update_datadog_feature_flag_environment` — updates flag env config
  - `update_datadog_workflow_with_agent_trigger` — adds agent trigger to workflow
  - `upsert_datadog_dashboard` — creates or updates dashboard
- **Read-only tools (highlights):**
  - `search_datadog_logs`, `search_datadog_metrics`, `search_datadog_monitors`, `search_datadog_dashboards`, `search_datadog_incidents`
  - `get_datadog_trace`, `get_datadog_metric`, `get_datadog_dashboard`, `get_datadog_incident`
  - APM toolset (15 tools, all read): `apm_search_spans`, `apm_explore_trace`, `apm_trace_summary`, `apm_latency_*`, `apm_*_watchdog_*`
  - Database Monitoring (11 tools): `find_datadog_database_instances`, `get_datadog_database_*`, `optimize_datadog_database_query`
  - DDSQL (6 tools): `ddsql_run_query`, `ddsql_schema_*`
  - Security: `datadog_secrets_scan`, `search_datadog_security_signals`, `get_datadog_security_signal`, `analyze_datadog_security_signals`, `analyze_security_findings`
- *(Full tool list in `snapshot.json`.)*

## MCP-specific risks
- **Tool-description injection scan:** Clean — descriptions are conventional product copy, no role-shifting language or embedded URLs targeting the model.
- **Suspicious descriptions:** none
- **Bundled local executors:** none locally; remote-side `ddsql_run_query` and `execute_datadog_workflow` are server-side execution channels — not local code execution but they extend blast radius if allowed.
- **Cross-tool shadowing risk:** Most names are `*_datadog_*`-prefixed which de-collides with other MCPs. `apm_*`, `ddsql_*`, `ndm_*` prefixes are NOT Datadog-namespaced — risk if a future MCP uses these prefixes.

## Supply chain
- **Install method:** remote-http (vendor-hosted endpoint, no local install)
- **Postinstall scripts:** No
- **Pinned by hash:** No (remote endpoint, version inferred from URL path `/api/unstable/...`)
- **Signed release / signed tags:** No (vendor-hosted)
- **npm provenance / Sigstore:** No (n/a)
- **Typosquat check performed:** Yes — no similar third-party packages found
- **Similar package names:** none
- **Maintainer 2FA:** n/a (vendor-hosted)

## Credentials & blast radius
- **Token / key storage:**
  - Local users: OAuth 2.0 tokens persisted by Claude Code's MCP OAuth flow in the OS-managed credential store (per-user).
  - Sandbox: `DD_API_KEY` + `DD_APPLICATION_KEY` are NOT persisted on disk — injected as env vars at Docker container start from **Keeper Secrets Manager**; the underlying Datadog application key is scoped to a read-only custom role.
- **OAuth scopes requested:** `mcp_read`, `mcp_write`
- **Minimum-necessary scopes:** No — `mcp_write` is requested by the OAuth flow but our allowlist does not need it. Mitigated by tightening at the Datadog role level (custom role with `mcp_read` only) for both engineers and the sandbox service principal.
- **Revocation mechanism:**
  - Local OAuth: revoke per-user grant via Datadog Personal Settings → Integrations or org admin (≤5 min).
  - Sandbox API+App key: rotate via KSM and revoke the application key in Datadog Organization Settings → Application Keys (≤15 min including KSM propagation to running containers).
- **Time to revoke:** 5 min (OAuth) / 15 min (sandbox key rotation via KSM)
- **Identity binding:** Personal (OAuth) for engineers; service-principal (KSM-injected app key) for sandboxes — dual mode.

## Local execution surface
- **Runs subprocess:** No
- **Eval / code generation:** No
- **Filesystem access:** Remote vendor service (no local code path)

## Data & ZDR
- **Data classes touched:** Confidential — operational telemetry, error traces, internal service names, customer-system identifiers; logs may incidentally contain PII unless aggressively scrubbed.
- **§3.2 corporate data source?:** No (observability, not SharePoint/Slack/Jira/Confluence/private-GitHub class)
- **ZDR-eligible:** No (no Anthropic ZDR commitment for tool egress)
- **Provider retention:** Logs/metrics/traces follow FMFX Datadog tenant retention (typically 15 days hot logs, 15 months metrics). MCP request/response handling retention not separately documented — see research gaps.

## Observability
- **Vendor-side audit log:** Available (Datadog Audit Trail)
- **Audit log retention:** Plan-tier dependent — confirm with platform team
- **Tool ships its own telemetry:** No (the MCP server is the API; no extra third-party analytics sink known)
- **Telemetry destinations:** none
- **Indirect injection vectors:**
  - `search_datadog_logs` / `search_datadog_events` — log lines may contain attacker-controlled URLs or prompts
  - `get_datadog_incident` / `search_datadog_cases` — case titles/comments are user-authored free text
  - `search_datadog_rum_events` — RUM events include URLs and form-field text from real browsers
  - `ddsql_run_query` — arbitrary SQL result rows from log/event tables
  - `ddsql_create_link` — returns a clickable URL the model may surface
  - `search_datadog_security_signals` / `get_datadog_security_signal` / `analyze_datadog_security_signals` — security signal payloads carry text from the original detection source (logs, events, network traffic)

## Compliance
- **Sub-processors** (verbatim from https://www.datadoghq.com/legal/subprocessors/ on 06 May 2026):
  - Amazon Web Services, Inc. — Infrastructure (US, AU, IT, JP, UK)
  - Anthropic, PBC — AI services (US)
  - Google LLC — Infrastructure / Email & office (US, DE)
  - Hyperdoc Inc. — Meeting transcription (US)
  - Mailgun Technologies, Inc. — Email (US)
  - Microsoft Corporation (Azure) — Infrastructure (US)
  - OpenAI, LLC — AI services (US)
  - Reversing Labs International GmbH — Threat intelligence (CH)
  - Salesforce, Inc. — Customer support (US)
  - Snowflake, Inc. — Data warehouse (US)
  - Twilio, Inc. — Communications (US)
  - Vonage Business, Inc. — Communications (US)
  - Zendesk, Inc. — Customer support (US)
- **Data residency:** Tenant data is EU at rest (Frankfurt) — endpoint `mcp.datadoghq.eu`. Cross-border transfer to US-based sub-processors (AI inference via OpenAI/Anthropic; CRM/support via Salesforce/Zendesk; comms via Twilio/Vonage/Mailgun) occurs in normal operation, covered by Datadog's DPA / Standard Contractual Clauses.
- **License compatibility:** Proprietary-SaaS
- **Vendor incident history:** none on record affecting the Datadog MCP server itself; ecosystem CVEs (CVE-2025-52882 Claude Code IDE, CVE-2025-49596 MCP Inspector, CVE-2025-6514 mcp-remote, postgres-MCP SQLi, CVE-2026-30623 LiteLLM MCP RCE, CVE-2026-35228 Oracle MCP Helper, CVE-2026-30615 Windsurf MCP injection) do not affect this remote-HTTP vendor service.

## Risk
- **Risk level:** Medium
- **Tier:** Elevated
- **Top risks:**
  - Prompt injection: Log/RUM/incident/security-signal content reaches the model unsanitised — high indirect-injection surface even with read-only allowlist.
  - Data exfiltration: Confidential telemetry (including incidental PII in logs) flows to Datadog's Bits AI which may sub-process to OpenAI/Anthropic.
  - Supply chain: Vendor-hosted SaaS — supply-chain risk reduces to Datadog's own breach posture (no recent incidents on record).
- **Known CVEs:** None found against the Datadog MCP server itself as of 06 May 2026.

## STRIDE quick-check

STRIDE is a threat-modelling mnemonic — six categories of things attackers do. The table below states the worst-case scenario for this tool in each:

- **Spoofing** — pretending to be someone you're not (stolen tokens, identity confusion).
- **Tampering** — unauthorised modification of data or behaviour.
- **Repudiation** — being able to deny that you did something (no audit trail).
- **Information disclosure** — leaking data that should stay private.
- **Denial of service** — making the system unavailable or unusable.
- **Elevation of privilege** — gaining capabilities you shouldn't have.

| Category | Worst-case |
|----------|------------|
| Spoofing | OAuth token theft impersonates the engineer until revocation (≤5 min). Sandbox key theft (from running container env or compromised KSM) impersonates the read-only service principal until KSM rotation (≤15 min). |
| Tampering | Prompt-injection drives mutating tools (monitors/dashboards/flags/workflows) — blocked by deny list. |
| Repudiation | Datadog Audit Trail attributes every call to the OAuth subject (engineer) or the application-key principal (sandbox). Sandbox calls attribute to the service principal, not an individual engineer — investigations must correlate with sandbox host/run logs to attribute to a person. |
| Info disclosure | Logs/RUM/traces with incidental PII reach the model and (via Bits AI) sub-processors. |
| Denial | `execute_datadog_workflow` or mass `create_datadog_monitor` could fire production workflows / exhaust quota — blocked. |
| Elevation | Datadog `mcp_write` permission granted at tenant gives an injected session full mutation scope across the org — restrict at the role level. |

## Compensating controls
- Deny-by-default on mutating tool patterns via managed `settings.json`.
- Datadog custom role granting `mcp_read` only — applied to BOTH engineer OAuth users and the sandbox service principal. Standard Role not used.
- Local users: OAuth 2.0 (personal identity binding).
- Sandbox: `DD_API_KEY` + `DD_APPLICATION_KEY` injected from KSM at container start — never written to image layers, .env files, or git-tracked config; KSM is the single rotation point.
- Endpoint locked to EU region.
- Re-snapshot on every allowlist change.
- Quarterly review of Datadog Audit Trail for unexpected MCP activity (especially failed denied-verb attempts and any sandbox traffic outside expected hours).

## Review schedule
- **Next review:** `13 Aug 2026`
- **Re-review triggers:**
  - New mutating tools appear in upstream snapshot diff
  - License or maintainer change
  - New CVE published against Datadog MCP or related Bits AI infra
  - Egress destination change
  - New Datadog sub-processor for AI inference

## Research gaps
- `retention` — MCP request/response logging retention not documented separately from Bits AI.
- `observability.vendor_audit_log_retention` — plan-tier dependent; confirm with platform.
- `compliance.sub_processors` — sourced verbatim from Datadog legal page on 06 May 2026; subscribe to the page for change notifications and re-snapshot on update.

## Changes since previous snapshot

- `[informational]` Two new Security tools enumerated upstream — both read-only, both fall under existing `analyze_*` / `get_*` allow patterns; no permission changes:
  - `analyze_datadog_security_signals` — analyses security signals via SQL.
  - `get_datadog_security_signal` — retrieves full details of a single security signal.
- `[informational]` Tool count reconciled — Datadog docs page now reports 123 tools and snapshot enumerates 123. Prior 121-vs-139 research gap closed.
- `[informational]` Removed `trial_period_days: 7` from `snapshot.json` — skill no longer tracks trial periods. Approval is binary; re-review cadence is 90 days post-approval by default with reviewer discretion to shorten via a condition.
- `[informational]` `review_due` updated in `snapshot.json` from `2026-05-13` (legacy 7-day-trial value) to `2026-08-13` to align with `adoption-record.md`'s manually-set value (replicates the reviewer-set re-review date).
- `[informational]` Re-rendered `adoption-record.md` against the current template — Decision section now sits at top (immediately after the header block); Distribution bullet added to Decision; STRIDE explainer block added before the worst-case table. All Decision content (Outcome, Conditions, Allowlist, Denylist, Token scope, Sandbox required) replicated verbatim from the prior render.
- `[informational]` Indirect-injection vectors list extended to cover the three security-signal tools (the two new ones plus `search_datadog_security_signals`).
- `[security-relevant]` Permission-string prefix corrected for plugin distribution — was `mcp__datadog-mcp__*`, now `mcp__plugin_freemarket-claude-skills_datadog__*` to match the runtime prefix Claude Code emits when the server is registered via the plugin's `.mcp.json`. Tagged security-relevant because a wrong prefix means the deny list silently does not apply (the patterns never match) — every mutating tool would default to allow. Both `settings.json` and the Decision § Allowlist/Denylist blocks are now aligned.
- `[security-relevant]` Allow / deny pattern shape switched from suffix-wildcard verb prefixes (e.g. `create_*`, `search_*`) to "namespace-wide allow + enumerated mutating-tool denies". Claude Code permission patterns only support a single trailing `*` over the entire tool-name segment — infix wildcards like `create_*` never matched at runtime, so the previous deny list was a no-op and every mutating tool defaulted to allow. New shape: one allow (`mcp__plugin_freemarket-claude-skills_datadog__*`) plus 25 explicit denies, one per `mutates: true` entry in `snapshot.json`. Both `settings.json` and Decision § Allowlist/Denylist updated together.

## Snapshot reference
- File: `tool-adoption-records/datadog-mcp/snapshot.json`
- Prior snapshots: `tool-adoption-records/datadog-mcp/history/`
