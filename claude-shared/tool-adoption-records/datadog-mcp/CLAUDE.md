# datadog-mcp — analysis source-of-truth

This file makes re-runs of the `tool-security-analysis` skill reproducible for this slug. Decisions captured here are inputs to the next run, not things to re-derive.

## Identity
- **Slug:** `datadog-mcp` (intentionally not region-qualified — FMFX uses one Datadog region (EU); a future US/AP adoption would warrant a separate slug like `datadog-mcp-us`)
- **Tool name:** Datadog MCP Server (EU)
- **Endpoint / version:** `https://mcp.datadoghq.eu/api/unstable/mcp-server/mcp` (path is the version identity — Datadog has not shipped a stable `/v1/`)
- **Vendor:** Datadog, Inc.

## Sources consulted
Re-runs MUST consult the same sources before deviating:

- https://docs.datadoghq.com/bits_ai/mcp_server/ (overview) — fetched 06 May 2026
- https://docs.datadoghq.com/bits_ai/mcp_server/setup/ (auth, transport, region endpoints) — fetched 06 May 2026
- https://docs.datadoghq.com/bits_ai/mcp_server/tools/ (canonical tool enumeration) — fetched 06 May 2026
- WebSearch: `"datadog mcp server" CVE OR vulnerability OR security advisory` — run 06 May 2026; no CVE found against the Datadog MCP server itself.

## Tool enumeration source
**Authoritative URL:** `https://docs.datadoghq.com/bits_ai/mcp_server/tools/`

That page is the single source of truth for the `tools[]` array in `snapshot.json`. Re-runs treat any tool not on that page as removed and any new tool there as added. Datadog's page summary states "139 total tools" — current snapshot enumerates 121 from the rendered tables; the gap is logged in `research_gaps[]` and should be reconciled on the next snapshot.

## Classification rationale
Decisions captured here MUST reproduce on re-run unless upstream data changes.

- **`data_classes: ["confidential"]`** — Datadog ingests application logs/metrics/traces from FMFX prod. Logs can incidentally carry PII or customer-system identifiers. Not "restricted" because PII is incidental, not the design intent; not "internal" because traces expose architecture and customer behaviour.
- **`is_section_3_2_source: false`** — observability platform, not SharePoint/Slack/Jira/Confluence/private-GitHub/Teams. Skill heuristic explicitly names "observability (Datadog)" as not §3.2.
- **`risk_level: medium`** — official vendor (Datadog), active, mature; large mutating surface (24 enumerated mutators + agentic onboarding execute tools); LLM-readable tool list of 121 entries. Medium with default-deny on writes; would be High if writes were allowed.
- **`tier: elevated`** — has write/delete/create surface AND HTTP transport to a novel vendor endpoint AND touches Confidential data. Any one of those triggers Elevated; this hits all three.

## Allow / deny derivation
Rule applied to derive `settings.json` patterns:

- **Wildcard constraint:** Claude Code permission patterns support only a single trailing `*` covering the entire tool-name segment. Infix / partial-name wildcards like `create_*` or `search_*` do NOT match at runtime — they silently never apply. Any deny list built from verb-prefix globs is therefore a no-op (every mutating tool defaults to allow). This rule replaces the round 1–5 prefix-glob approach.
- **Allow:** a single namespace-wide pattern `mcp__plugin_freemarket-claude-skills_datadog__*` covers every Datadog MCP tool.
- **Deny:** enumerate every tool with `mutates: true` in `snapshot.json` by full name. Re-derive on every snapshot diff: any new mutating tool MUST be added to the deny list before the approval extends to the new snapshot. This currently yields 25 entries — all `create_*`, `update_*`, `upsert_*`, `delete_*`, `edit_*`, `append_*`, `sync_*`, `execute_*`, `link_*`, `add_comment_*` tools, all `*_onboarding` tools, `synthetics_test_wizard` (read-shaped name, mutating effect), and `source_map_uploads`.
- **No deny on read-only tools.** New read-only tools added by Datadog are auto-allowed by the namespace wildcard; this is intentional and matches the medium-risk classification (the boundary is "no mutations", not "explicit allowlist of every read").

## MCP server name
- **Permission-string prefix:** `mcp__plugin_freemarket-claude-skills_datadog__<tool>`
- **Plugin name:** `freemarket-claude-skills` (the production plugin; the server is declared in the plugin's `.mcp.json`)
- **Server name (within plugin):** `datadog`
- **Justification:** Because Datadog is distributed via the `freemarket-claude-skills` plugin's `.mcp.json`, Claude Code prefixes its tool names with `mcp__plugin_<plugin-name>_<server-name>__`. The server name inside `.mcp.json` is `datadog` (not `datadog-mcp`); the `-mcp` suffix only appears in the adoption-record slug to identify the *kind* of integration on disk. Permission strings in `settings.json` MUST match the runtime-emitted prefix exactly — there is no glob fallback. Locking this here prevents drift on re-run.
- **Anti-drift note:** `mcp__datadog-mcp__*` (without the `plugin_` prefix) is the pattern that would apply if the server were registered locally per-engineer instead of via the plugin. The plugin path is canonical at FMFX; do NOT regenerate `settings.json` against the bare-server pattern.

## Reviewer feedback log

### 06 May 2026 — round 1
- **Feedback (verbatim):**
  - "change the slug to be datadog-mcp"
  - "'API+App key alternative discouraged' we are going to inject read-only scoped app/api key as environment variables in docker sandbox environments. This will be automated with values retrieved from Keeper Secrets Manager. For all use by local users, we would expect this to be OAuth. Decision needs amending to refrect this."
  - "data residency in EU, but subprocessors do exist outside of this so your research is correct"
  - "subprocessor list - https://www.datadoghq.com/legal/subprocessors/#third-party-subprocessors"
- **Decision:**
  - Renamed directory `datadog-mcp-eu` → `datadog-mcp`; updated `slug`, identity sections, and snapshot path references everywhere.
  - Reframed auth as a two-mode model rather than "OAuth preferred, key-pair discouraged". Sandbox path is now a first-class condition: KSM-injected DD_API_KEY/DD_APPLICATION_KEY against a Datadog application key bound to a read-only custom role. Updated `auth.notes`, `credentials.storage_location`, `credentials.identity_binding` (now `other` to reflect dual mode), `credentials.revocation_mechanism`, `credentials.time_to_revoke_minutes` (5 → 15 to reflect KSM propagation), STRIDE `spoofing` and adoption-record Repudiation row, decision conditions, and compensating controls.
  - Confirmed data-residency framing: kept the EU-at-rest + cross-border-to-US-subprocessors text.
  - Replaced inferred sub-processor list with verbatim list from https://www.datadoghq.com/legal/subprocessors/ (13 entries with regions). Removed the "verify before commit" research gap; replaced with a "subscribe to the page" cadence note.
- **Files updated:** `snapshot.json`, `adoption-record.md`, `CLAUDE.md` (this file). `settings.json` unchanged — server name `datadog-mcp` was already locked.

### 06 May 2026 — round 2 (re-run after skill update)
- **Feedback (verbatim):** "update the skill so that reviewed and review due dates are written using the format 'dd MMM yyyy' in md files / after running a review, only display the suggested commit message text AFTER we have completed the final feedback cycle / commit the skill (update previous commit) / Once done, re-run the review of this mcp server to make sure the dates are updated as requested in the md file."
- **Decision:** Skill amended in commit 122f169 (date-format split: ISO in JSON, `dd MMM yyyy` in MD; commit message moved to Phase 4b.12 after feedback loop closes). Re-ran the review against the unchanged upstream Datadog MCP data — no security-relevant deltas — and re-rendered all human-facing dates in `adoption-record.md` and this file using `dd MMM yyyy`. Prior snapshot archived to `history/2026-05-06-snapshot.json`. The `snapshot.json` content itself did not change (reviewed_on still 06 May 2026).
- **Files updated:** `adoption-record.md`, `CLAUDE.md` (this file). `snapshot.json` unchanged. `settings.json` unchanged.

### 06 May 2026 — round 3 (re-review after skill iteration on already-approved tools)
- **Feedback (verbatim):**
  - "it has been approved which is why status line is set as it is - do not change that"
  - "approved means no longer in trial, but re-review scheduled for 3 months following approval date"
  - "distribution is new in the skill, it should be added as part of this review"
  - "do we need to make further changes to the skill to cater for tools which have already been approved to comply with these rules?" → followed by: "lose the concept of trial in this skill altogether. engineers can request access. infosec will review and either approve or decline. If approved, a 90 day re-approval comes into force unless a condition is added to the approval which reduces this time period. that is up to the discretion of the reviewer." Skill code changes deferred ("Skip for now") — captured as gaps below.
- **Decision:**
  - **Status preserved.** `Approved-with-conditions` retained verbatim; not re-derived as `Proposed`.
  - **Lost the trial concept.** Removed `trial_period_days: 7` from `snapshot.json`. New rule (verbal): approval is binary; re-review default = approval date + 90 days; reviewer may shorten via a Decision condition.
  - **Replicated reviewer-set `Review due`.** Prior `adoption-record.md` value `13 Aug 2026` retained (manual override under existing skill rule); `snapshot.json` `review_due` updated `2026-05-13` → `2026-08-13` to match.
  - **Distribution bullet added.** Decision section re-rendered against current template (Decision now at top); Distribution bullet present, populated by the post-feedback-loop prompt later in this run.
  - **Upstream delta accepted.** Datadog docs added two read-only Security tools — both fall under existing allow patterns; `settings.json` unchanged. Indirect-injection vectors extended to cover the three security-signal tools.
  - **Tool gap closed.** Datadog page now reports 123 tools and we enumerate 123 — removed the 121-vs-139 entry from `research_gaps[]`.
- **Files updated:** `snapshot.json`, `adoption-record.md`, `CLAUDE.md` (this file). `settings.json` unchanged. No new history archive — current `snapshot.json` (pre-edit) was byte-identical to existing `history/2026-05-06-snapshot.json`.
- **Skill gaps deferred for separate change (user said "Skip for now"):**
  - No first-class `status` field in `snapshot.schema.json`. Status lives only in MD header line and is invisible to the determinism contract. Should become an enum: `proposed | approved-with-conditions | approved | rejected | retired`.
  - Review-due default of `reviewed_on + 30 days` is wrong for already-approved tools. Should branch on status: fresh/proposed → 30d; approved* → 90d. Manual override should still win.
  - Phase 1 doesn't ask whether this is a fresh review, post-trial confirmation, or routine re-review of an approved tool. Branch on it.
  - Manual-edit detection in step 3 currently lists "Status changes" but has no first-class concept of *preserving* an approval state on re-render. Tighten so a re-run cannot silently regress a `Approved-with-conditions` tool back to `Proposed`.
  - Determinism contract should list `status` as one of the fields that MUST reproduce on re-run.

### 06 May 2026 — round 4 (distribution captured; mid-review skill iteration)
- **Feedback (verbatim):**
  - "before we continue with the review, please update skill.md as previously requested. no more trial concept; approved tools get 90-day re-review by default with reviewer discretion to shorten"
  - "explicit \"Approved*\" MUST NOT silently regress to Proposed. That includes \"Approved\" and \"Approved-with-conditions\" - update the skill for that"
  - "commit the skill changes before we continue with the review"
  - Distribution mechanism (verbatim): "Datadog mcp is distributed as part of the freemarket-claude-skills plugin within .mcp.json. This gets loaded automatically into client sessions when the plugin is initialised. Clients will need to follow the OAuth flow to authenticate with Datadog by running /plugin and navigating to the `Datadog MCP Server` within the `freemarket-claude-skills` plugin, then selecting `Authenticate`. Managed settings control the tool MCP server permissions." (reworded into Decision § Distribution sub-bullets)
- **Decision:**
  - Skill amended in commit `423e815` (`feat(tool-security-analysis): drop trial concept; default 90-day re-review; protect Approved* from silent regression`). `trial_period_days` removed from schema; review-due default 30→90 days; reviewer-discretion-to-shorten clause added; explicit Approved* anti-regression rule added; plugin/marketplace bumped 1.25.0 → 1.25.1.
  - Distribution captured in `adoption-record.md` as three sub-bullets (server registration via `.mcp.json` in the plugin, per-engineer OAuth via `/plugin → Datadog MCP Server → Authenticate`, permissions via managed `settings.json`).
- **Files updated:** `skills/tool-security-analysis/SKILL.md`, `skills/tool-security-analysis/snapshot.schema.json`, `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` (committed as `423e815` separately from this adoption record). `tool-adoption-records/datadog-mcp/adoption-record.md`, `tool-adoption-records/datadog-mcp/CLAUDE.md` (this file).

### 06 May 2026 — round 5 (permission-string prefix corrected for plugin distribution)
- **Feedback (verbatim):** "when datadog mcp is distributed with the plugin, allow/deny rules look slightly different from what is in settings.json. need to update to follow this pattern \"mcp__plugin_freemarket-claude-skills_datadog__<tool_name>\" and remember that in CLAUDE.md"
- **Decision:**
  - The bare-server prefix `mcp__datadog-mcp__` only applies when an engineer registers the MCP server locally. Because FMFX distributes Datadog via the `freemarket-claude-skills` plugin's `.mcp.json`, the runtime prefix is `mcp__plugin_freemarket-claude-skills_datadog__` (the server name inside `.mcp.json` is `datadog`, not `datadog-mcp`). Permission strings in `settings.json` MUST match the runtime-emitted prefix exactly — no glob fallback.
  - Updated all 33 patterns in `settings.json` and the matching code blocks in `adoption-record.md` § Decision (Allowlist + Denylist).
  - Updated `CLAUDE.md` § MCP server name with plugin name, server name, justification, and an anti-drift note. Updated determinism contract to lock the new prefix and capture `status: Approved-with-conditions`.
- **Files updated:** `tool-adoption-records/datadog-mcp/settings.json`, `tool-adoption-records/datadog-mcp/adoption-record.md`, `tool-adoption-records/datadog-mcp/CLAUDE.md` (this file).

### 11 May 2026 — round 7 (allow/deny rewritten: namespace allow + enumerated mutating denies)
- **Feedback (verbatim):** "settings in C:\dev\git\claude-shared\tool-adoption-records\datadog-mcp\settings.json use wildcards for partial tool names, but this is not supported. lets add a global allow for \"mcp__plugin_freemarket-claude-skills_datadog__*\" and add explicit deny for all write tools"
- **Decision:**
  - Claude Code permission patterns support only a trailing `*` over the entire tool-name segment. Infix wildcards (`create_*`, `search_*`, `apm_*`) never matched at runtime, so the previous prefix-glob deny list was a no-op and every mutating tool defaulted to allow. This is security-relevant.
  - Replaced the 16 allow patterns with a single namespace-wide allow: `mcp__plugin_freemarket-claude-skills_datadog__*`.
  - Replaced the 18 deny patterns with 25 enumerated full-name denies — one per `mutates: true` tool in `snapshot.json` (every `create_*`, `update_*`, `upsert_*`, `delete_*`, `edit_*`, `append_*`, `sync_*`, `execute_*`, `link_*`, `add_comment_*` plus all `*_onboarding`, `synthetics_test_wizard`, and `source_map_uploads`).
  - Documented the wildcard constraint in CLAUDE.md § Allow/deny derivation so future re-runs don't regress to prefix-globs.
  - Logged as a `[security-relevant]` entry in adoption-record.md § Changes since previous snapshot.
- **Files updated:** `tool-adoption-records/datadog-mcp/settings.json`, `tool-adoption-records/datadog-mcp/adoption-record.md`, `tool-adoption-records/datadog-mcp/CLAUDE.md` (this file).

### 06 May 2026 — round 6 (sandbox README reference added to Distribution)
- **Feedback (verbatim):** "under distribution in the .md, we need to include a reference to https://github.com/FreemarketFX/claude-shared/blob/main/ralph-sandbox/mcp/datadog/README.md for instruction on using the Datadog MCP Server in sandboxes."
- **Decision:** Added a fourth sub-bullet under Decision § Distribution pointing engineers to the sandbox setup README. The OAuth path covers local interactive use; this URL covers the KSM-injected key-pair path for Ralph / Docker sandboxes.
- **Files updated:** `tool-adoption-records/datadog-mcp/adoption-record.md`, `tool-adoption-records/datadog-mcp/CLAUDE.md` (this file).

## Determinism contract
On a re-run with unchanged upstream data (same tools page, no new CVE, no policy change), these fields MUST reproduce byte-identically:

- `slug: datadog-mcp`
- `name: "Datadog MCP Server (EU)"`
- `vendor: "Datadog, Inc."`
- `official_vendor: true`
- `transport: https`
- `data_classes: ["confidential"]`
- `is_section_3_2_source: false`
- `risk_level: medium`
- `tier: elevated`
- `auth.method: oauth2` (OAuth is the schema-level method; sandbox key-pair path documented in `auth.notes`)
- `auth.scopes: ["mcp_read", "mcp_write"]`
- `credentials.identity_binding: other` (dual mode: personal OAuth for engineers + service-principal key-pair for sandboxes)
- `credentials.time_to_revoke_minutes: 15` (worst-case across both auth modes)
- Permission-string prefix `mcp__plugin_freemarket-claude-skills_datadog__` (plugin-distributed) and the allow/deny rule above
- `status: Approved-with-conditions` (binding decision; MUST NOT regress on re-run)
- `compensating_controls[]` — exact text

**Permitted to drift:** `reviewed_on`, `review_due`. Anything else changing without an upstream change is a re-run drift bug.
