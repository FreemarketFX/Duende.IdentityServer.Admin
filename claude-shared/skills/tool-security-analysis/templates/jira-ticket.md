# Tool Approval Request — <tool name>

## Summary
- **Tool:** <name>
- **Type:** MCP Server | Skill | Plugin | Command | Hook
- **Source:** <URL>
- **Version proposed:** <pinned version>
- **Official vendor:** Yes | No
- **Package manager:** npm | PyPI | other
- **Recommended tier:** Standard | Elevated | Emergency
- **Risk level:** Low | Medium | High

## Requester
- **Engineer:** <name, email>
- **Business justification:** <one or two sentences>

## Maintainer trust signals
- **Stars / downloads:** <e.g. GitHub 12k stars, 50k npm weekly downloads>
- **First release:** <date>
- **Latest release:** <date + version>
- **Release cadence:** <monthly / quarterly / sporadic / stale>
- **Open security issues:** <count and link>
- **Maintainer(s):** <individual / org / vendor-operated>
- **License:** <MIT / Apache / etc.>

## Technical surface
- **Transport:** stdio | HTTP(S) | other
- **Declared tools:** <list with one-line description per tool>
- **Network egress:** <domains the tool will call>
- **Credentials required:** <type, scope>
- **Dependencies:** <count, notable runtime deps>
- **Known CVEs:** <list, or "None found as of <date>">

## Data classification
- **Data classes the tool will access:** Public | Internal | Confidential | Restricted
- **§3.2 corporate data source?:** Yes | No (if Yes, Policy §14 exception is required)
- **ZDR impact:** <MCP traffic is not ZDR-eligible; note implication>

## Proposed configuration
- **Allowlist (tools permitted):**
  ```
  mcp__<server>__<tool_a>
  mcp__<server>__<tool_b>
  ```
- **Denylist (tools explicitly blocked):**
  ```
  mcp__<server>__*write*
  mcp__<server>__*delete*
  mcp__<server>__*create*
  ```
- **Token scope:** <minimum scope that makes the tool work>
- **Sandbox required:** Yes | No (Yes for HTTP transport or unaudited source)
- **Pinned version:** <exact version>

## Threat surface (quick read)
- **Tool descriptions reviewed for injection:** Yes / No — <flagged tools or "clean">
- **Bundled local executors:** <tool names or "none">
- **Install method:** remote-http | npm | pypi | other; **postinstall scripts:** Yes/No; **pinned/signed:** Yes/No
- **Token storage:** <location>; **scopes requested:** <list>; **minimum-necessary:** Yes/No
- **Time to revoke on compromise:** <minutes>
- **Local exec / eval:** Yes/No; **filesystem access:** <paths or "remote only">
- **Vendor-side audit log:** Yes/No; **tool's own telemetry:** Yes/No (<destinations>)
- **Sub-processors / data residency:** <region>; **license:** <SPDX>; **vendor incidents on record:** <list or "none">

## STRIDE summary
- **S**poofing: <one sentence>
- **T**ampering: <one sentence>
- **R**epudiation: <one sentence>
- **I**nfo disclosure: <one sentence>
- **D**enial: <one sentence>
- **E**levation: <one sentence>

## Risks identified
- **Prompt injection surface:** <which tool results return untrusted text>
- **Data exfiltration surface:** <what the tool could exfiltrate given full session context>
- **Supply-chain concerns:** <dependency or maintainer concerns>
- **Provider retention:** <what the provider keeps, and for how long>

## Compensating controls proposed
- <e.g. "Output scanning hook must be active">
- <e.g. "Monitor for denied-tool invocation attempts">
- <e.g. "90-day trial, auto-review">

## Open questions for InfoSec
- <anything the engineer couldn't resolve>

## Skill-generated on <date>
