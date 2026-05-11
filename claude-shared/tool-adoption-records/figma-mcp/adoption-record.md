# Adoption Record — Figma Remote MCP Server

> Status: **Approved-with-conditions** (See [Decision](#Decision))
> Snapshot: `https://github.com/FreemarketFX/claude-shared/tool-adoption-records/figma-mcp/snapshot.json`
> Reviewed: `11 May 2026` by `Rob Taylor` — Review due: `09 Aug 2026`
> Owner: **InfoSec and Platform Team**

## Decision
- **Outcome:** Approved-with-conditions
- **Conditions / scope limits:**
  - `use_figma` (general-purpose write to Design + FigJam) is approved for use but MUST NOT be auto-approved — it is intentionally absent from both `allow` and `deny` in `settings.json` so Claude Code prompts the user on every invocation. This makes the "human-in-the-loop on every `use_figma` call" acceptable-use guideline a technical enforcement, not just a behavioural one. Every other mutating tool stays denied; opening any of them requires re-review, not an in-place edit.
  - Beta product — re-review on any new tool appearing upstream, regardless of read/write classification, because Figma's tool catalog is actively expanding.
  - Per-user OAuth only — no shared service-principal account, no PAT (Figma does not support PATs for MCP anyway). Each developer authorises individually so the audit trail attributes to a real person.
  - Re-review when Figma exits beta and switches to usage-based pricing; pricing exit may also flip the data-handling posture.
  - Confidential design IP (unreleased product, brand, partner co-brand) MAY pass through this MCP; Restricted material (customer PII, real payment screens) MUST NOT — handle via the standard Figma UI under the existing data-handling controls instead.
  - **Prompt-injection PostToolUse defender MUST stay registered for `mcp__.*`** in `hooks/hooks.json`. The matcher is in place as of 11 May 2026 and the defender is a load-bearing layer on the injection-to-mutation path. Re-review if the matcher is removed, narrowed below `mcp__.*`, or if the defender hook is unloaded for any reason.
- **Acceptable-use guidelines for end users:** these are the behavioural conditions under which `use_figma` is approved — violating any one of them invalidates the approval and the user MUST disable the connector until they can return to compliance.
  - **Internal-authored canvases only.** Files the MCP touches must be authored and edited exclusively by FMFX-internal Figma users. Do not invoke any MCP tool against a file with external editors, external commenters, or guest seats on the access list. External-collaboration files are out of scope for the MCP entirely — comments, frame names, text-node content, and component descriptions become attacker-controlled inputs that flow into `get_design_context` / `get_figjam` / `get_metadata` and can steer `use_figma` into mutating the design system on the attacker's behalf.
  - **No public / community imports before invocation.** Do not import frames, components, or files from the Figma Community, public templates, or third-party libraries into a canvas immediately before invoking the MCP. Treat any externally-sourced node as untrusted text until it has been manually audited and renamed.
  - **Resolve external comment threads first.** Files with open comment threads from external accounts (even if those accounts no longer have edit access) MUST have those threads resolved or deleted before MCP use; comment bodies are read by `get_design_context` and are an indirect-injection surface.
  - **Operate on duplicates of canonical files.** When iterating with the model on the design system, brand library, or any shared production file, duplicate it first and run `use_figma` against the copy. Merge curated changes back into the canonical file manually via the Figma UI — do not point the MCP at the canonical source.
  - **Human-in-the-loop for every `use_figma` invocation.** `use_figma` is intentionally NOT on the auto-approve allowlist — Claude Code will prompt on every call (technical enforcement via `settings.json`). Do not bypass the prompt by adding `use_figma` to a local `allow` list, running under "yolo" / unattended mode, or pre-approving the tool for a session. Read each prompt before accepting; if the prompted action does not match what you asked Claude to do, deny it — that is the signal of a successful injection.
  - **Narrow prompts only.** Keep MCP prompts scoped to a specific frame, component, or selection ("update the spacing on this frame's children"). Avoid broad prompts ("clean up the file", "fix the design system") — broad prompts widen the surface that injected instructions can hijack.
  - **No Restricted content in any file the MCP touches.** Customer PII, real payment-screen data, regulated KYC artefacts, and similar Restricted material MUST never appear in a file the MCP reads from or writes to.
  - **Rely on Figma version history for rollback.** Confirm Figma file history is intact for any file before invoking `use_figma`; if an unexpected edit lands, recover via Figma's UI version history rather than chat-transcript context. Do not rely on the model's understanding of "the prior state".
- **Distribution:**
  - **Connector availability:** The Figma MCP connector is activated in Claude Code org settings on claude.ai, so it is available to all Claude Code users automatically. Only users with an active Figma account can complete the OAuth handshake and use the server.
  - **Permission enforcement:** Managed settings enforce which tools can be used. The `settings.json` in this directory (`tool-adoption-records/figma-mcp/settings.json`) is the source-of-truth allow / prompt-on-every-call / deny configuration; how it reaches developer machines is governed by the platform Claude Code managed-settings distribution mechanism.
  - **Egress allow-list:** `https://mcp.figma.com/mcp` has been added to `allowedMcpServers` in managed settings, so Claude Code will only connect to the Figma-controlled endpoint and cannot be redirected to an arbitrary MCP server impersonating the connector.
- **Allowlist** (auto-approved):
  ```
  mcp__claude_ai_Figma__get_code_connect_map
  mcp__claude_ai_Figma__get_code_connect_suggestions
  mcp__claude_ai_Figma__get_design_context
  mcp__claude_ai_Figma__get_figjam
  mcp__claude_ai_Figma__get_metadata
  mcp__claude_ai_Figma__get_screenshot
  mcp__claude_ai_Figma__get_variable_defs
  mcp__claude_ai_Figma__search_design_system
  mcp__claude_ai_Figma__whoami
  ```
- **Prompt-on-every-call** (approved for use, NOT auto-approved — Claude Code's default ask-the-user behaviour applies because the tool appears in neither `allow` nor `deny`):
  ```
  mcp__claude_ai_Figma__use_figma
  ```
- **Denylist** (blocked):
  ```
  mcp__claude_ai_Figma__add_code_connect_map
  mcp__claude_ai_Figma__create_design_system_rules
  mcp__claude_ai_Figma__create_new_file
  mcp__claude_ai_Figma__generate_diagram
  mcp__claude_ai_Figma__generate_figma_design
  mcp__claude_ai_Figma__send_code_connect_mappings
  ```
- **Token scope:** Per-user OAuth managed by Figma's MCP server; scopes are not client-configurable. Bound to the developer's individual Figma identity and the org's existing access controls.
- **Sandbox required:** No — remote vendor service, no local execution surface.

## Identity
- **Name:** Figma Remote MCP Server
- **Slug:** figma-mcp
- **Type:** MCP Server
- **Source:** https://help.figma.com/hc/en-us/articles/35281350665623-Figma-MCP-collection-How-to-set-up-the-Figma-remote-MCP-server-preferred
- **Version / endpoint path:** `https://mcp.figma.com/mcp`
- **Vendor / maintainer:** Figma, Inc. (official vendor)
- **License:** Proprietary-SaaS

## Surface
- **Transport:** HTTPS (vendor-hosted at `https://mcp.figma.com/mcp`)
- **Auth:** OAuth 2.0 — Figma-managed flow; client-side scopes opaque (PAT auth explicitly unsupported).
- **Network egress:** `figma.com`, `mcp.figma.com`, `www.figma.com`
- **Dependencies (notable):** none (vendor-hosted remote service; no local package).
- **Tool count:** 16 (9 read-only auto-approved, 1 mutating prompt-on-every-call, 6 mutating denied)
- **Mutating tools:**
  - `add_code_connect_map` — adds Figma node ↔ code component mapping
  - `create_design_system_rules` — creates a rule file for design-to-code agents
  - `create_new_file` — creates a new blank Design / FigJam file in the user's drafts
  - `generate_diagram` — generates a FigJam diagram from Mermaid / NL
  - `generate_figma_design` — generates Design layers from passed-in interfaces
  - `send_code_connect_mappings` — persists Code Connect mapping suggestions
  - `use_figma` — *general-purpose write* tool: create/edit/delete any object in a Design file or FigJam board
- **Read-only tools (highlights):**
  - `get_design_context` — React + Tailwind structured view of the selection
  - `get_variable_defs` — variables and styles in selection
  - `get_screenshot` — visual snapshot of selection
  - `search_design_system` — search connected libraries for components, variables, styles
  - `whoami` — authenticated user identity
- *(Full tool list in `snapshot.json`.)*

## MCP-specific risks
- **Tool-description injection scan:** Clean — descriptions are mechanical (`Returns…`, `Creates…`, `Captures…`); no role-shifting language, embedded URLs, or model-targeted instructions.
- **Suspicious descriptions:** none.
- **Bundled local executors:** none — `use_figma` writes to Figma objects, not the local machine; no shell/eval/run_code surface. Note `use_figma` is a *remote* general-purpose mutator, so it sits in a different threat class than local executors (browser_evaluate, bash) but carries an analogous "model can do anything in scope" property at the Figma object level.
- **Cross-tool shadowing risk:** Low — `mcp__<server>__<tool>` namespacing prevents collision with `datadog-mcp` (`search_*`) or `playwright-mcp` (`browser_*`). Re-evaluate if a future MCP exposes `get_design_*` or a competing `use_*` write tool.

## Supply chain
- **Install method:** remote-http (no local package).
- **Postinstall scripts:** No.
- **Pinned by hash:** No (n/a for remote service).
- **Signed release / signed tags:** No (n/a for remote service).
- **npm provenance / Sigstore:** No (n/a for remote service).
- **Typosquat check performed:** Yes — `mcp.figma.com` is the documented Figma-controlled host; no typosquat-shaped npm/pypi package consumed.
- **Similar package names:** none (no local package).
- **Maintainer 2FA:** n/a (vendor-hosted by Figma).

## Credentials & blast radius
- **Token / key storage:** Claude Code's MCP OAuth client stores the refresh / access token in the OS credential manager (Windows) via Claude Code's secure-storage layer.
- **OAuth scopes requested:** opaque to the client — Figma's MCP server controls the scope set internally; not user-configurable, not exposed to the MCP catalog client.
- **Minimum-necessary scopes:** No — the client cannot enumerate or constrain the scope set, so minimum-necessary cannot be asserted. Compensating control: every mutating tool is denied at the Claude Code permission layer, so even if Figma grants write capability, the model cannot invoke it.
- **Revocation mechanism:** Per-user revocation in Figma > Settings > Security > Authorized apps; admin-level revocation via Figma org admin console.
- **Time to revoke:** ~5 minutes.
- **Identity binding:** Personal — actions attribute to the developer's individual Figma identity.

## Local execution surface
- **Runs subprocess:** No.
- **Eval / code generation:** No.
- **Filesystem access:** remote vendor service.

## Data & ZDR
- **Data classes touched:** Confidential — FMFX product UI mockups, design system artifacts, brand and partner co-brand assets, unreleased product designs.
- **§3.2 corporate data source?:** No — Figma is a design tool, not a SharePoint/Slack/Jira/Confluence/Outlook/Teams integration (per skill heuristic).
- **ZDR-eligible:** No — Figma is a SaaS provider; data handling is governed by Figma's master ToS / DPA, not a zero-data-retention contract.
- **Provider retention:** Figma retains design-file contents per the user's plan; MCP-specific request/response retention not documented — see research gaps.

## Observability
- **Vendor-side audit log:** Available — Figma enterprise audit log (file-level events).
- **Audit log retention:** Per Figma enterprise plan; MCP-tool-invocation granularity unverified — see research gaps.
- **Tool ships its own telemetry:** No (no local component).
- **Telemetry destinations:** none.
- **Indirect injection vectors:**
  - `get_design_context` — frame names, text nodes, and component descriptions are author-controllable; a hostile shared library could embed instructions.
  - `get_figjam` — sticky-note and shape text on shared boards is author-controllable.
  - `get_metadata` — node names and properties are author-controllable.
  - `search_design_system` — library component names / descriptions are author-controllable.
  - `get_screenshot` — image content can carry vision-model-targeted instructions.

## Compliance
- **Sub-processors:** Figma's general sub-processor list applies (https://www.figma.com/legal/sub-processors/); MCP-specific delta unverified — see research gaps.
- **Data residency:** Figma global infrastructure (primarily US); MCP endpoint region routing unverified — see research gaps.
- **License compatibility:** Proprietary-SaaS.
- **Vendor incident history:** No data-disclosure incidents on record specifically tied to the MCP product as of 11 May 2026 (product is in beta, no public CVE / advisory).

## Risk
- **Risk level:** Medium
- **Tier:** Elevated
- **Top risks:**
  - Prompt injection → in-Figma mutation: a hostile element (frame name, text node, comment thread, sticky note, library component description) on a file landed in `get_design_context` / `get_figjam` / `get_metadata` / `search_design_system` steers the model into invoking `use_figma` to mutate the file (delete frames, rewrite text, restructure the design system). This is now a closed loop — the deny-on-every-mutator compensating control is gone. Mitigated by the acceptable-use guidelines (internal-only canvases, no community imports, resolve external comments, work on duplicates, human-in-the-loop approval, narrow prompts) — those guidelines are the load-bearing control, not a permission-layer deny.
  - Data exfiltration: `get_design_context` / `get_screenshot` / `search_design_system` against an FMFX-internal Figma file place Confidential design IP into the chat transcript and onward to the API provider. ZDR-ineligible vendor; mitigated by personal-identity binding, the existing Figma org access controls (the MCP can only see what the user already could), and the guideline excluding Restricted content from any MCP-touched file.
  - Design-system corruption: `use_figma` can — through a misunderstood instruction, not necessarily a hostile one — delete or restructure shared library files in ways that propagate downstream. Mitigated by the "operate on duplicates" guideline and Figma's native version history (rollback path).
  - Supply chain: vendor-hosted, so the typical npm/PyPI threat surface does not apply; residual risk is Figma the company being compromised — outside FMFX's control beyond contractual posture.
- **Known CVEs:** None published as of 11 May 2026.

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
| Spoofing | A stolen OAuth refresh token in the developer's OS credential store grants the attacker the authenticated user's full Figma org access until the user revokes the authorised app. |
| Tampering | A hostile element in a file the user reads via the MCP (frame name, comment thread, sticky note, library component description) steers `use_figma` into modifying a production design file or design-system library; mitigated by the internal-only-canvas guideline and the human-in-the-loop approval requirement on every `use_figma` call, but the injection-to-mutation path is architecturally present. |
| Repudiation | Figma audit-log granularity for MCP tool invocations is unverified, so a misuse via MCP may be indistinguishable from the same user's regular UI activity. |
| Info disclosure | A read tool (`get_design_context` / `get_screenshot` / `search_design_system`) exfiltrates Confidential design IP from FMFX libraries into the chat transcript and onward to the API provider. |
| Denial | Figma rate-limits or OAuth-token revocation interrupts every developer using the MCP simultaneously; impact is loss-of-productivity, not data loss. |
| Elevation | OAuth scope creep — Figma silently widening the granted scope set at a future consent screen — would grant capabilities the adoption record did not anticipate; the personal identity binding caps blast radius at the consenting user's existing Figma permissions. |

## Compensating controls
- Managed `settings.json` denies every mutating tool EXCEPT `use_figma` (`create_new_file`, `generate_figma_design`, `generate_diagram`, `add_code_connect_map`, `send_code_connect_mappings`, `create_design_system_rules` all denied).
- Acceptable-use guidelines (see Decision § Acceptable-use guidelines) are the load-bearing control on the prompt-injection-to-mutation path now that `use_figma` is allowed: internal-only canvases, no community imports, resolve external comment threads before MCP use, operate on duplicates of canonical files, human-in-the-loop approval on every `use_figma` call, narrow prompts only, exclude Restricted content from any MCP-touched file.
- **Prompt-injection PostToolUse defender** (`hooks/prompt-defender-pwsh/post-tool-defender.ps1`, distributed via the `claude-shared` / `freemarket-claude-skills` plugin) — pattern-based scanner that runs after each registered tool call, inspects the tool output for known indirect-prompt-injection signatures (instruction-override, role-play / DAN, hidden-HTML-comment, ANSI / ASCII-smuggler, system-role JSON, etc.), warns Claude when matches fire, and emits a Datadog telemetry record. **In scope for this MCP** — `hooks/hooks.json` registers the defender against the `mcp__.*` PostToolUse matcher, so every `mcp__claude_ai_Figma__*` invocation's output is scanned before Claude continues. This is a defence-in-depth layer behind the acceptable-use guidelines: it catches injection content the user didn't pre-empt by following the guidelines, and it makes guideline violations observable in Datadog telemetry.
- Per-user OAuth identity (no service principal, no shared secret); revocation is one click in Figma's user settings (~5 minutes).
- Figma's MCP server only accepts approved client identifiers (Claude Code, Cursor, VS Code, Codex); rogue MCP clients cannot complete the OAuth handshake.
- Single hostname egress (`mcp.figma.com`) over HTTPS; no local subprocess, no host filesystem access.
- Figma file version history provides the recovery path for any `use_figma` edit, hostile or accidental.
- Re-review trigger on any new mutating tool added upstream; Figma's tool catalog is an active beta and the surface can grow.

## Review schedule
- **Next review:** `09 Aug 2026`
- **Re-review triggers:**
  - New tool appears in upstream snapshot diff (read OR write — beta surface).
  - Any tool's `mutates` flag flips false → true.
  - Figma exits beta or transitions to usage-based pricing.
  - License or vendor change.
  - New CVE or vendor data-disclosure incident published.
  - Supported-clients list changes (e.g. Claude Code is removed from the catalog, or a new client family is added that affects org policy).

## Research gaps
- `auth.scopes` — Figma's MCP OAuth handshake does not expose user-configurable scopes; the `mcp:connect` scope is internal and not documented externally.
- `retention` — MCP-specific request/response retention is not stated in the public help articles or developer docs as of 11 May 2026.
- `compliance.sub_processors` — Figma's general sub-processor list covers the platform; whether the MCP introduces additional sub-processors is not separately documented.
- `compliance.data_residency` — MCP endpoint region routing is not documented separately from Figma's general posture.
- `observability.vendor_audit_log_retention` — granularity of MCP tool invocations in Figma's enterprise audit log is undocumented.
- `supply_chain.signed_release` — n/a for vendor-hosted remote service.

## Snapshot reference
- File: `tool-adoption-records/figma-mcp/snapshot.json`
- Prior snapshots: `tool-adoption-records/figma-mcp/history/` (none — fresh adoption record)
