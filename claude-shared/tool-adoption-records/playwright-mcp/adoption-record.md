# Adoption Record — Playwright MCP

> Status: **Approved-with-conditions** (See [Decision](#Decision))
> Snapshot: `https://github.com/FreemarketFX/claude-shared/tool-adoption-records/playwright-mcp/snapshot.json`
> Reviewed: `08 May 2026` by `Rob Taylor` — Review due: `06 Aug 2026`
> Owner: **InfoSec and Platform Team**

## Decision
- **Outcome:** Approved-with-conditions
- **Conditions / scope limits:**
  - Container image MUST stay pinned by digest (currently `mcr.microsoft.com/playwright/mcp:v0.0.75@sha256:d238ec7bc98cc4e22df0696d6031dad5b8a4b46781f4f0abaa3bfadeedb43b9a`); any image bump MUST update the digest in `ralph-sandbox/mcp/playwright/compose.yml` AND re-run this adoption record. Reverting to a tag-only reference is not permitted.
  - HTTP MCP endpoint MUST remain bound to loopback only; `--allowed-hosts` MUST stay set to `localhost:8931,127.0.0.1:8931`.
  - `--isolated` flag MUST stay on — no persistent browser profile, no storage-state file mounted from the host.
  - Optional capability buckets MUST stay off in the deployment compose: do not pass `--caps=vision|pdf|devtools|network|storage|testing`. Re-review required before enabling any of these — each unlocks new mutating tools (`browser_route`, `browser_storage_state`, `browser_pdf_save`, `browser_mouse_*_xy`, etc.).
  - `playwright.allowedDomains` in `proxy-config.yml` MUST be the only mechanism for granting navigation access; do not start the server without `PLAYWRIGHT_MCP_ALLOWED_ORIGINS` populated outside Ralph sandbox mode.
  - In-sandbox mode MUST keep routing all egress through `host.docker.internal:3128` with the proxy CA cert injected, so a single inspectable choke point captures every navigated URL.
- **Distribution:** Reference: [README.md](https://github.com/FreemarketFX/claude-shared/ralph-sandbox/mcp/playwright/README.md).
Docker Compose service distributed via the `claude-shared` git subtree under `ralph-sandbox/mcp/playwright/` — `compose.yml` (base: digest-pinned image, loopback port, healthcheck, `playwright-net` bridge), `compose-sandbox.yml` (sandbox overrides: host-network mode, proxy env vars, proxy CA cert path), and `compose-sandbox-startup.sh` (post-start hook that copies the sandbox proxy CA into the container and registers it in Chromium's NSS store). Activation paths:
  - **Sandbox (Ralph):** the sandbox entrypoint reads `tasks/config/mcp-servers.yml`, pulls the image, starts the container, and auto-generates the `.mcp.json` consumed by Claude Code. Example entry:

    ```yaml
    servers:
      playwright:
        type: http
        url: http://localhost:8931/mcp
        docker:
          compose: playwright/compose.yml
          allowedOriginsEnvVar: PLAYWRIGHT_MCP_ALLOWED_ORIGINS  # only required by mcp-startup.ps1 for local execution
          proxyConfigSection: playwright                        # only required by mcp-startup.ps1 for local execution
    ```

  - **Local developer:** `claude-shared/ralph-sandbox/mcp/mcp-startup.ps1` (PowerShell Core + Docker Desktop) reads the same `mcp-servers.yml`, applies `allowedOriginsEnvVar: PLAYWRIGHT_MCP_ALLOWED_ORIGINS` derived from `config/proxy-config.yml` → `playwright.allowedDomains`, starts the container, and writes `.mcp.json`. `mcp-startup.ps1 -Down` removes both.
  - **Egress allow-list:** managed centrally in `config/proxy-config.yml` under the `playwright.allowedDomains` section; `Sync-ProxyConfig` in `ralph-sandbox.ps1` merges every per-server `allowedDomains` into the flat `network.allowedDomains` array of the generated `proxy-config.json`. Example:

    ```yaml
    playwright:
      allowedDomains:
        - "*.wearefreemarket.com"
        - "*.example.com"
    ```

  - **Permission allow/deny (this adoption record):** the `settings.json` in this directory is the source-of-truth; how it reaches developer machines (managed-settings precedence vs. plugin-shipped vs. consumer-repo `.claude/settings.json` merge) is governed by the platform Claude Code distribution mechanism, not by this tool.
- **Allowlist:**
  ```
  mcp__playwright__browser_click
  mcp__playwright__browser_close
  mcp__playwright__browser_console_messages
  mcp__playwright__browser_drag
  mcp__playwright__browser_drop
  mcp__playwright__browser_file_upload
  mcp__playwright__browser_fill_form
  mcp__playwright__browser_handle_dialog
  mcp__playwright__browser_hover
  mcp__playwright__browser_navigate
  mcp__playwright__browser_navigate_back
  mcp__playwright__browser_network_request
  mcp__playwright__browser_network_requests
  mcp__playwright__browser_press_key
  mcp__playwright__browser_resize
  mcp__playwright__browser_select_option
  mcp__playwright__browser_snapshot
  mcp__playwright__browser_tabs
  mcp__playwright__browser_take_screenshot
  mcp__playwright__browser_type
  mcp__playwright__browser_wait_for
  ```
- **Denylist:**
  ```
  mcp__playwright__browser_evaluate
  mcp__playwright__browser_run_code_unsafe
  ```
- **Token scope:** None — MCP endpoint is unauthenticated on loopback; per-site auth lives in the in-memory browser context only.
- **Sandbox required:** No — approved for both Ralph sandbox and local-developer Docker Desktop modes, but the local-developer mode loses the egress choke point. Prefer sandbox mode for any work that may navigate to FMFX-internal sites.

## Identity
- **Name:** Playwright MCP
- **Slug:** playwright-mcp
- **Type:** MCP Server
- **Source:** https://github.com/microsoft/playwright-mcp
- **Version / endpoint path:** `mcr.microsoft.com/playwright/mcp:v0.0.75@sha256:d238ec7bc98cc4e22df0696d6031dad5b8a4b46781f4f0abaa3bfadeedb43b9a` (multi-arch OCI index digest)
- **Vendor / maintainer:** Microsoft (official vendor)
- **License:** Apache-2.0

## Surface
- **Transport:** HTTP (loopback `http://localhost:8931/mcp`, gated by `--allowed-hosts`)
- **Auth:** None on the MCP endpoint; in-page sessions live in the ephemeral browser context only.
- **Network egress:** `*.wearefreemarket.com` (default `proxy-config.yml`), `host.docker.internal:3128` (sandbox proxy hop), `mcr.microsoft.com` (one-time image pull).
- **Dependencies (notable):** `@playwright/mcp@0.0.75`, `playwright`, `@modelcontextprotocol/sdk` — all bundled inside the container image.
- **Tool count:** 23 (8 read-only, 15 mutating)
- **Mutating tools:**
  - `browser_click` — click an element
  - `browser_close` — close the active page
  - `browser_drag` — drag-and-drop between elements
  - `browser_drop` — drop files / MIME data onto a target
  - `browser_evaluate` — *(denied)* execute a JavaScript expression in the page
  - `browser_file_upload` — upload files into a file input
  - `browser_fill_form` — fill multiple form fields at once
  - `browser_handle_dialog` — accept / dismiss dialogs
  - `browser_hover` — hover the pointer
  - `browser_navigate` — navigate to a URL
  - `browser_navigate_back` — history back
  - `browser_press_key` — press a keyboard key
  - `browser_resize` — resize the viewport
  - `browser_run_code_unsafe` — *(denied)* execute arbitrary Playwright code
  - `browser_select_option` — select a `<select>` option
  - `browser_tabs` — manage tabs
  - `browser_type` — type into an editable element
- **Read-only tools (highlights):**
  - `browser_snapshot` — accessibility-tree snapshot
  - `browser_take_screenshot` — page screenshot
  - `browser_console_messages` — captured console log
  - `browser_network_requests` / `browser_network_request` — request inventory + details
  - `browser_wait_for` — wait for text or duration
- *(Full tool list in `snapshot.json`.)*

## MCP-specific risks
- **Tool-description injection scan:** Clean — descriptions are imperative-but-mechanical (`Click an element`, `Navigate to a URL`); no role-shifting language, embedded URLs, or model-targeted instructions.
- **Suspicious descriptions:** none.
- **Bundled local executors:** `browser_evaluate`, `browser_run_code_unsafe` — both denied via managed `settings.json`.
- **Cross-tool shadowing risk:** Low today — all tools are `browser_*`-prefixed; no clash with `datadog-mcp` (`search_*` / `get_*` / `aggregate_*`). Re-evaluate if any future MCP exposes `browser_*` tools.

## Supply chain
- **Install method:** container (OCI image from Microsoft Container Registry)
- **Postinstall scripts:** No — image is pulled, not installed via a package manager on the host.
- **Pinned by hash:** Yes — `compose.yml` uses `mcr.microsoft.com/playwright/mcp:v0.0.75@sha256:d238ec7bc98cc4e22df0696d6031dad5b8a4b46781f4f0abaa3bfadeedb43b9a`. The tag is retained alongside the digest for human readability; Docker enforces the digest match.
- **Signed release / signed tags:** Yes (with caveat) — `docker buildx imagetools inspect` shows Docker BuildKit attestation manifests (SLSA provenance + SBOM) attached to both `linux/amd64` and `linux/arm64`. Microsoft-identity Sigstore / cosign verification was NOT performed.
- **npm provenance / Sigstore:** No (Sigstore not in use for this image).
- **Typosquat check performed:** Yes — confirmed `mcr.microsoft.com/playwright/mcp` is the Microsoft-published path. Similar-looking npm packages exist (`@executeautomation/playwright-mcp-server` is an unrelated community fork) but are not consumed by this deployment.
- **Similar package names:** `@executeautomation/playwright-mcp-server`, `@playwright/test` (different products).
- **Maintainer 2FA:** n/a (vendor-hosted by Microsoft via MCR).

## Credentials & blast radius
- **Token / key storage:** in-memory only (no persistent profile because `--isolated` is set).
- **OAuth scopes requested:** none.
- **Minimum-necessary scopes:** Yes — the MCP endpoint requires no auth and the tool itself holds no FMFX-issued credentials.
- **Revocation mechanism:** `docker compose down` on the playwright service removes the container and tears down the listener; no shared API key or OAuth grant to rotate.
- **Time to revoke:** ~1 minute.
- **Identity binding:** Service principal — actions taken via this MCP are attributable only to the developer's Claude Code transcript, not to a per-user vendor identity.

## Local execution surface
- **Runs subprocess:** Yes — the container process spawns headless Chromium.
- **Eval / code generation:** Yes — `browser_evaluate` runs JS in the page; `browser_run_code_unsafe` runs arbitrary Playwright code. Both denied in the approved configuration.
- **Filesystem access:** Per-session output to `/tmp/playwright-output` (sandbox) or the `playwright-data` named volume (local). No host bind-mounts.

## Data & ZDR
- **Data classes touched:** Internal, Confidential — `playwright.allowedDomains` defaults include `*.wearefreemarket.com`, which can resolve to FMFX-internal admin and portal surfaces.
- **§3.2 corporate data source?:** No — Playwright MCP is generic browser automation, not a SharePoint/Slack/Jira/Confluence/Outlook integration. (Note: it *can* be pointed at such surfaces; that risk lives in the `allowedDomains` review, not in the tool itself.)
- **ZDR-eligible:** Yes — self-hosted container, no third-party data path.
- **Provider retention:** None vendor-side. Local container retains per-session artefacts under `/tmp/playwright-output` for the container's lifetime only.

## Observability
- **Vendor-side audit log:** Not available — self-hosted.
- **Audit log retention:** n/a.
- **Tool ships its own telemetry:** No — no built-in analytics phoned home.
- **Telemetry destinations:** none.
- **Indirect injection vectors:**
  - `browser_snapshot` — accessibility-tree text is attacker-controllable on any navigated page.
  - `browser_take_screenshot` — image content can carry vision-model-targeted instructions.
  - `browser_console_messages` — page console output is attacker-controllable.
  - `browser_network_requests` / `browser_network_request` — captured response bodies are attacker-controllable.
  - `browser_navigate` — once a hostile site is loaded, every read tool that follows reflects its content.

## Compliance
- **Sub-processors:** none (self-hosted).
- **Data residency:** Local to the developer machine / sandbox container; egress is governed by `playwright.allowedDomains` and the sandbox proxy.
- **License compatibility:** Permissive (Apache-2.0).
- **Vendor incident history:** No advisories on record for `microsoft/playwright-mcp` as of 08 May 2026 (`https://github.com/microsoft/playwright-mcp/security/advisories` empty).

## Risk
- **Risk level:** Medium
- **Tier:** Elevated
- **Top risks:**
  - Prompt injection: a navigated page injects instructions into the accessibility tree or console messages and the model executes them on subsequent tool calls — partially mitigated by denying `browser_evaluate` and the sandbox proxy log, but the `browser_navigate` → read-tool feedback loop is intrinsic.
  - Data exfiltration: `browser_navigate` to an internal page followed by `browser_snapshot` / `browser_take_screenshot` can ex-filtrate Confidential data into the chat transcript and the API provider — bounded by `allowedDomains` and ZDR eligibility.
  - Supply chain: digest-pinned to the multi-arch OCI index, so an upstream tag overwrite cannot swap the image content; residual risk is a compromise of MCR itself between the digest being recorded here and the next image bump, plus reliance on Microsoft's BuildKit attestation chain (no separate cosign verification step in the deployment).
- **Known CVEs:** None published as of 08 May 2026.

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
| Spoofing | A malicious page reached via `browser_navigate` impersonates a trusted FMFX internal site, tricking the model into submitting credentials via `browser_fill_form`. |
| Tampering | `browser_evaluate` / `browser_run_code_unsafe` rewrite the DOM mid-flow and falsify a screenshot the developer is using as evidence (mitigated: both denied). |
| Repudiation | Container destruction loses local state; without retained sandbox proxy logs and Claude Code transcripts, after-the-fact investigation is impossible. |
| Info disclosure | A `browser_navigate` + `browser_snapshot` pair ex-filtrates Confidential content from a reachable internal site into the chat transcript. |
| Denial | A runaway `browser_evaluate` or unbounded navigation pins container CPU and starves other MCP traffic on the developer's machine. |
| Elevation | `browser_run_code_unsafe` combined with `--no-sandbox` (Chromium setuid sandbox off) plus a Chromium 0-day yields container-root code execution; bounded by container + proxy (mitigated: tool denied). |

## Compensating controls
- `--isolated` enforced — no persistent browser profile, cookies, or storage state across sessions.
- `PLAYWRIGHT_MCP_ALLOWED_ORIGINS` populated from `playwright.allowedDomains` restricts navigation to an explicit allow-list.
- `--allowed-hosts localhost:8931,127.0.0.1:8931` plus loopback bind eliminate remote MCP access.
- Sandbox-mode egress forced through `host.docker.internal:3128` with proxy CA cert injected into Chromium NSS — single inspectable choke point.
- Digest-pinned image (`v0.0.75@sha256:d238ec7bc98cc4e22df0696d6031dad5b8a4b46781f4f0abaa3bfadeedb43b9a`) prevents both `latest`-tag drift and silent tag-overwrite of `v0.0.75`; image bumps must update the digest in `compose.yml` and trigger a re-review.
- Managed `settings.json` denies `browser_evaluate` and `browser_run_code_unsafe`, removing the model→arbitrary-code paths.
- Container is ephemeral and runs `--headless --no-sandbox` with no host bind-mounts; blast radius bounded to the container.

## Review schedule
- **Next review:** `06 Aug 2026`
- **Re-review triggers:**
  - New mutating tools appear in upstream snapshot diff (e.g. opt-in caps surface).
  - License or maintainer change (e.g. a fork is adopted instead).
  - New CVE published for `@playwright/mcp` or the bundled Chromium / Playwright versions.
  - `playwright.allowedDomains` changed to include any new corporate-data-source surface (Confluence, Jira, SharePoint, etc.) — would flip §3.2 status.
  - Image upgrade beyond `v0.0.75`.
  - Any opt-in capability flag (`--caps=...`) added to the compose command.

## Research gaps
- `supply_chain.signed_release` — recorded as Yes based on Docker BuildKit attestation manifests (SLSA provenance + SBOM) seen via `docker buildx imagetools inspect`; Microsoft-identity Sigstore / cosign verification was NOT performed. Treat the "Yes" as evidence of build-time provenance, not as identity-bound signature verification.
- `supply_chain.maintainer_2fa` — Microsoft GitHub org membership 2FA is not externally verifiable; treated as `n/a-vendor-hosted`.
- Capability-gated tools (`--caps=vision|pdf|devtools|network|storage|testing`) — out of scope for this snapshot because the deployment leaves them off; documented as a re-review trigger.
- `observability.vendor_audit_log_available` — n/a (self-hosted); FMFX must rely on container stdout, sandbox proxy access logs, and Claude Code's tool-use transcripts.

## Snapshot reference
- File: `tool-adoption-records/playwright-mcp/snapshot.json`
- Prior snapshots: `tool-adoption-records/playwright-mcp/history/`
