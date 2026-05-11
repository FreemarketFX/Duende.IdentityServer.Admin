# Adoption Record — <tool name>

> Status: **Proposed | Approved | Approved-with-conditions | Rejected | Retired** (See [Decision](#Decision))
> Snapshot: `tool-adoption-records/<slug>/snapshot.json`
> Reviewed: `<dd MMM yyyy>` by `<reviewer>` — Review due: `<dd MMM yyyy>`
> Owner: **InfoSec and Platform Team**

## Decision
- **Outcome:** Approved | Approved-with-conditions | Rejected
- **Conditions / scope limits:** <bulleted; e.g. read-only allowlist, region-locked endpoint>
- **Distribution:** <approved distribution / configuration mechanism — populated from end-of-review prompt; e.g. managed settings.json shipped via Claude Code plugin, MDM-pushed managed settings, container image baked with config, KSM-injected env vars>
- **Allowlist:**
  ```
  <tool patterns>
  ```
- **Denylist:**
  ```
  <tool patterns>
  ```
- **Token scope:** <minimum>
- **Sandbox required:** Yes | No

## Identity
- **Name:** <name>
- **Slug:** <slug>
- **Type:** MCP Server | Skill | Plugin | Command | Hook
- **Source:** <URL>
- **Version / endpoint path:** <pinned version or remote path>
- **Vendor / maintainer:** <official vendor | community | individual>
- **License:** <SPDX identifier>

## Surface
- **Transport:** stdio | HTTPS | other
- **Auth:** <OAuth scopes | API key headers | none>
- **Network egress:** <comma-separated domains>
- **Dependencies (notable):** <name@version, ...>
- **Tool count:** <total> (<read-only count> read-only, <mutating count> mutating)
- **Mutating tools:**
  - `<tool_name>` — <one-line description>
- **Read-only tools (highlights):**
  - `<tool_name>` — <one-line description>
- *(Full tool list in `snapshot.json`.)*

## MCP-specific risks
- **Tool-description injection scan:** Clean | Flagged
- **Suspicious descriptions:** <`tool` — reason; or "none">
- **Bundled local executors:** <tool names that wrap arbitrary exec; or "none">
- **Cross-tool shadowing risk:** <name-collision notes when running alongside other MCPs>

## Supply chain
- **Install method:** remote-http | npm | pypi | cargo | go-install | binary | container | git-clone
- **Postinstall scripts:** Yes | No
- **Pinned by hash:** Yes | No
- **Signed release / signed tags:** Yes | No
- **npm provenance / Sigstore:** Yes | No
- **Typosquat check performed:** Yes | No
- **Similar package names:** <list or "none">
- **Maintainer 2FA:** Yes | No | Unknown | n/a (vendor-hosted)

## Credentials & blast radius
- **Token / key storage:** <location>
- **OAuth scopes requested:** <list>
- **Minimum-necessary scopes:** Yes | No (if No, justify)
- **Revocation mechanism:** <how access is cut on compromise>
- **Time to revoke:** <minutes>
- **Identity binding:** Personal | Service principal | Shared secret | Other

## Local execution surface
- **Runs subprocess:** Yes | No
- **Eval / code generation:** Yes | No
- **Filesystem access:** <paths or "remote vendor service">

## Data & ZDR
- **Data classes touched:** Public | Internal | Confidential | Restricted
- **§3.2 corporate data source?:** Yes | No
- **ZDR-eligible:** Yes | No
- **Provider retention:** <duration + what is retained>

## Observability
- **Vendor-side audit log:** Available | Not available
- **Audit log retention:** <duration>
- **Tool ships its own telemetry:** Yes | No
- **Telemetry destinations:** <list or "none">
- **Indirect injection vectors:** <tool outputs that may carry injection content; e.g. log lines, ticket descriptions, URLs Claude may WebFetch>

## Compliance
- **Sub-processors:** <list>
- **Data residency:** <region routing>
- **License compatibility:** Permissive | Weak-copyleft | Strong-copyleft | Commercial-restricted | Proprietary-SaaS | Unknown
- **Vendor incident history:** <recent advisories or "none on record">

## Risk
- **Risk level:** Low | Medium | High
- **Tier:** Standard | Elevated | Emergency
- **Top risks:**
  - Prompt injection: <one line>
  - Data exfiltration: <one line>
  - Supply chain: <one line>
- **Known CVEs:** <list or "None found as of <dd MMM yyyy>">

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
| Spoofing | <one sentence> |
| Tampering | <one sentence> |
| Repudiation | <one sentence> |
| Info disclosure | <one sentence> |
| Denial | <one sentence> |
| Elevation | <one sentence> |

## Compensating controls
- <bullet>
- <bullet>

## Review schedule
- **Next review:** `<dd MMM yyyy>`
- **Re-review triggers:**
  - New mutating tools appear in upstream snapshot diff
  - License or maintainer change
  - New CVE published
  - Egress destination change

## Research gaps
- <field — reason research could not resolve it>

## Changes since previous snapshot
*(Populated only on re-snapshot. Each delta tagged `[security-relevant]` or `[informational]`.)*

- <delta>

## Snapshot reference
- File: `tool-adoption-records/<slug>/snapshot.json`
- Prior snapshots: `tool-adoption-records/<slug>/history/`
