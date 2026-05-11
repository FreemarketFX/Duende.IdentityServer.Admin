# Figma Remote MCP — Adoption-Record Determinism Contract

## Identity
- **Slug:** `figma-mcp`
- **Tool name:** Figma Remote MCP Server
- **Endpoint / version:** `https://mcp.figma.com/mcp` (HTTPS, vendor-hosted)
- **Vendor:** Figma, Inc. (`figma.com`)

## Sources consulted
- `https://help.figma.com/hc/en-us/articles/35281350665623-Figma-MCP-collection-How-to-set-up-the-Figma-remote-MCP-server-preferred` — setup instructions, plan requirements — fetched 08 May 2026.
- `https://help.figma.com/hc/en-us/articles/32132100833559-Guide-to-the-Figma-MCP-server` — MCP server overview — referenced 08 May 2026.
- `https://developers.figma.com/docs/figma-mcp-server/` — developer documentation index — fetched 08 May 2026.
- `https://developers.figma.com/docs/figma-mcp-server/remote-server-installation/` — endpoint URL, OAuth flow, supported clients, beta pricing — fetched 08 May 2026.
- `https://developers.figma.com/docs/figma-mcp-server/tools-and-prompts/` — canonical tool list with read/write classification and remote/desktop availability — fetched 08 May 2026.
- Figma forum threads on OAuth scope availability (`mcp:connect` not exposed externally) and PAT non-support — referenced 08 May 2026.

## Tool enumeration source
Authoritative list: `https://developers.figma.com/docs/figma-mcp-server/tools-and-prompts/`. Re-runs MUST consult this URL and reconcile against the snapshot's `tools[]`. The remote-server scope INCLUDES "Remote only" tools (`generate_figma_design`, `generate_diagram`, `whoami`, `use_figma`, `search_design_system`, `create_new_file`); desktop-only tools are excluded by definition. "Both" classification means the tool is exposed by the remote server too.

## Classification rationale
- **`data_classes`: `confidential`** — confirmed by reviewer (08 May 2026). FMFX product UI mockups, design system artifacts, brand and partner co-brand assets, and unreleased product designs sit at Confidential. Restricted is excluded by Decision condition (customer PII / live payment screens are not the documented use case for this MCP). Internal alone is too narrow because brand and unreleased-product material qualifies as Confidential under FMFX policy §5.
- **`is_section_3_2_source`: false** — design tools are explicitly excluded from §3.2 by the skill heuristic (which lists SharePoint / Outlook / Slack / Jira / Confluence / private GitHub / Teams as the §3.2 set). Figma is not in that family.
- **`risk_level`: medium** — official vendor (Figma), HTTPS to a single Figma-controlled hostname, no local subprocess, no FMFX-issued credentials. Counter-pressure that prevents Low: a general-purpose write tool (`use_figma`) plus six other mutating tools are present on the surface (denied at the permission layer, but architecturally reachable), the product is in beta with an actively expanding tool catalog, and OAuth scopes are opaque to the client (cannot assert minimum-necessary). High is not warranted because the vendor is well-known and there is no published CVE or unfixable architectural flaw.
- **`tier`: elevated** — skill rule forces Elevated whenever a tool "introduces write/delete/create operations" OR "runs HTTP transport to a novel endpoint". The Figma MCP does both. Cannot be downgraded to Standard regardless of allow/deny posture.

## Allow / deny derivation
**Rule:** Three-tier permission posture, not the usual two:

1. **Auto-approve** (in `settings.json` `permissions.allow`): read-shaped verbs only (`get_*`, `search_*`, `whoami`).
2. **Prompt on every call** (in NEITHER `allow` NOR `deny` — Claude Code's default ask-the-user behaviour): `use_figma` only. The intentional absence from `allow` is the technical enforcement of the "human-in-the-loop" acceptable-use guideline.
3. **Deny** (in `settings.json` `permissions.deny`): every other mutating tool.

Applied to the 16-tool surface:

- **Auto-approve** (9): `get_code_connect_map`, `get_code_connect_suggestions`, `get_design_context`, `get_figjam`, `get_metadata`, `get_screenshot`, `get_variable_defs`, `search_design_system`, `whoami`.
- **Prompt-on-every-call** (1): `use_figma`.
- **Deny** (6): `add_code_connect_map`, `create_design_system_rules`, `create_new_file`, `generate_diagram`, `generate_figma_design`, `send_code_connect_mappings`.

`use_figma` is approved because the FMFX use case requires Claude to author and modify Design / FigJam canvases on the developer's behalf. Its blast radius is contained by (a) Claude Code's per-call approval prompt (this list-membership choice), (b) the acceptable-use guidelines in the adoption-record Decision section (internal-only canvases, no community imports, resolve external comments, duplicate canonical files before MCP use, narrow prompts, exclude Restricted content), (c) the prompt-injection PostToolUse defender registered on `mcp__.*`, and (d) Figma's native version history as the rollback path.

The other mutating tools stay denied because:

- `create_new_file` — out of scope; file creation is a deliberate human action, not a model action.
- `generate_figma_design` / `generate_diagram` — `use_figma` covers equivalent ground; keeping both denied narrows the surface without losing capability.
- `add_code_connect_map` / `send_code_connect_mappings` — Code Connect mappings affect downstream code generation across the org; not part of the current use case.
- `create_design_system_rules` — modifies agent-guidance rule files; out of scope.

If a future re-run adds new tools, apply the same rule recursively: deny by default unless the tool fits the design-iteration use case AND can be governed by an analogous behavioural guideline; allow read-shapes (`get_*` / `search_*` / `list_*` / `whoami` / `describe_*` / equivalent).

## MCP server name
`claude_ai_Figma` — confirmed by reviewer on 11 May 2026 by observing the `mcp__claude_ai_Figma__whoami` tool name surfaced locally for the org-managed connector (`Config location: claude.ai` in `/mcp`). Permission strings therefore have the shape `mcp__claude_ai_Figma__<tool>`. This is NOT the slug-minus-qualifier default (`figma`) — the Anthropic-managed connector uses its own registration identifier with display-name-derived casing and underscore separators. Locked here so re-runs do not drift back to `mcp__figma__*`.

## Reviewer feedback log

### 11 May 2026 — round 1
- **Feedback (verbatim):** "mcp__claude_ai_Figma__whoami is the org managed permissions structure / update settings:permissions to reflect this"
- **Decision:** The MCP is consumed via the org-managed Anthropic connector ("Claude.ai Figma MCP Server", `Config location: claude.ai`), not a `.mcp.json` entry, so the permission-string server token is `claude_ai_Figma`, not the `figma` default. Replaced every `mcp__figma__*` with `mcp__claude_ai_Figma__*` in `settings.json` and the adoption-record Allowlist / Denylist; updated the MCP-server-name section above to lock the new identifier.
- **Files updated:** `settings.json`, `adoption-record.md`, `CLAUDE.md`.

### 11 May 2026 — round 6
- **Feedback (verbatim):** "add full url to the snapshot path and change to approved.  look at playwright or datadog for the url prefix."
- **Decision:** Updated the header block in `adoption-record.md`: snapshot path rewritten to the full `https://github.com/FreemarketFX/claude-shared/tool-adoption-records/figma-mcp/snapshot.json` URL (matching the playwright-mcp convention), and Status flipped from `Proposed` to `Approved-with-conditions` to match the Decision § Outcome. Per skill rules this is now a binding decision and MUST be replicated verbatim on any re-run; never silently regress to `Proposed`.
- **Files updated:** `adoption-record.md`, `CLAUDE.md`.

### 11 May 2026 — round 5
- **Feedback (verbatim):** "lets not auto-approve use_figma to ensure users are prompted to approve running the tool"
- **Decision:** Removed `mcp__claude_ai_Figma__use_figma` from `settings.json` `permissions.allow`. Did NOT add it to `deny` — adding it to `deny` would block the tool entirely; the goal is "prompt the user every time", which Claude Code does by default when a tool appears in neither list. Reframed the adoption-record permission posture as three-tier (auto-approve / prompt-on-every-call / deny) instead of two-tier (allow / deny), with `use_figma` now in the explicit prompt-on-every-call tier. Updated the Decision section, the human-in-the-loop guideline (now technically enforced via list-membership, not just behaviourally), the Surface tool-count breakdown, and the determinism contract. Moving `use_figma` into either list at a future revision invalidates the approval and forces re-review.
- **Files updated:** `settings.json`, `adoption-record.md`, `CLAUDE.md`.

### 11 May 2026 — round 4
- **Feedback (verbatim):** "check now to see if defender is covering the mcp tool output"
- **Decision:** Re-read `hooks/hooks.json` and confirmed the PostToolUse matcher list now includes `mcp__.*` (lines 162-171) wired to `prompt-defender-pwsh/post-tool-defender.ps1`. Every `mcp__claude_ai_Figma__*` invocation is therefore in scope of the injection scanner. Updated the compensating-control entry in `snapshot.json` and `adoption-record.md` to remove the "scope gap" caveat and reframe the defender as a defence-in-depth layer with Datadog observability. Replaced the "extend the matcher list" Decision condition with a "matcher MUST stay registered for `mcp__.*`" condition that re-triggers a review if the registration is removed or narrowed.
- **Files updated:** `snapshot.json`, `adoption-record.md`, `CLAUDE.md`.

### 11 May 2026 — round 3
- **Feedback (verbatim):** "a compensating control would be our prompt defender installed with the freemarket-claude-skills plugin which inspects tool output and alerts if prompt injection is detected"
- **Decision:** Added the prompt-injection PostToolUse defender (`hooks/prompt-defender-pwsh/post-tool-defender.ps1`, distributed via the `claude-shared` / `freemarket-claude-skills` plugin) to `compensating_controls[]` in both `snapshot.json` and the adoption record. Verified the hook exists and is registered in `hooks/hooks.json` for `PostToolUse` matchers `Read`, `WebFetch`, `Bash`, `Grep`, `Task`. **Important honesty caveat:** none of those matchers cover `mcp__claude_ai_Figma__*` tool names, so the defender is NOT currently a Figma-MCP-path control. Recorded the scope gap on the compensating-control entry and added a Decision condition requiring the matcher list to be extended (e.g. `mcp__claude_ai_Figma__.*` or `mcp__.*`) plus the standard plugin version bump before the control becomes load-bearing for this MCP. Until then, acceptable-use guidelines remain the sole defence on the prompt-injection-to-mutation path.
- **Files updated:** `snapshot.json`, `adoption-record.md`, `CLAUDE.md`.

### 11 May 2026 — round 2
- **Feedback (verbatim):** "we need to enable the use_figma tool for our use-case. Please re-evaluate and update the adoption record. Within the descision block, lets add some acceptable usage guidelines for end users of this mcp server (clear + concise bullet points) which help mitigate the risks of allowing access to this tool. Note things like canvases can only be authored and modified by internal users to prevent prompt injection through comments, frame nodes, descriptions etc. + any other advice which would be meaningful and justified."
- **Decision:** Moved `use_figma` from deny to allow in `settings.json` and the adoption-record Allowlist/Denylist; updated the allow/deny derivation rule above to reflect that the design-iteration use case requires it. Added an **Acceptable-use guidelines for end users** bullet block inside the Decision section covering: internal-authored canvases only (no external editors/commenters/guest seats), no public/community imports before MCP invocation, resolve external comment threads first, operate on duplicates of canonical files, human-in-the-loop approval on every `use_figma` call (no auto-approve), narrow prompts only, no Restricted content in MCP-touched files, rely on Figma version history for rollback. Rewrote the prompt-injection top-risk row (no longer "bounded by deny-list on every mutator" — that compensating control is gone; guidelines are now the load-bearing control), added a "Design-system corruption" top-risk row, rewrote the STRIDE Tampering row, updated `compensating_controls[]` in both files, and added a new `research_gaps[]` entry recording that the acceptable-use guidelines have no automated enforcement layer. `reviewed_on` advanced to 11 May 2026 and `review_due` to 09 Aug 2026.
- **Files updated:** `settings.json`, `snapshot.json`, `adoption-record.md`, `CLAUDE.md`.

## Determinism contract
On re-run with unchanged upstream data, the following decisions MUST reproduce verbatim:

- **`slug`:** `figma-mcp` (matches the `<tool>-mcp` convention used by sibling adoption records: `datadog-mcp`, `playwright-mcp`).
- **MCP server name:** `claude_ai_Figma` — confirmed from the org-managed Anthropic connector's actual permission strings; used to construct `mcp__claude_ai_Figma__*` permission strings.
- **`risk_level`:** `medium`
- **`tier`:** `elevated`
- **`is_section_3_2_source`:** `false`
- **`data_classes`:** `confidential`
- **Allow/deny rule:** three-tier — auto-approve read-shaped verbs only, leave `use_figma` in neither list so Claude Code prompts on every call, deny every other mutating tool. The "prompt-on-every-call" status for `use_figma` is the technical enforcement of the human-in-the-loop guideline; moving `use_figma` into either `allow` or `deny` invalidates the approval and requires re-review.
- **Tool enumeration scope:** every tool listed at the developer-docs URL whose availability is "Both" or "Remote only"; "Desktop only" tools are out of scope.

The only fields permitted to change without an upstream change are `reviewed_on` and `review_due` (the calendar advances).
