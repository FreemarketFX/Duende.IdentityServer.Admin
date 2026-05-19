# PRD: Docker Sandbox Network Policies

## Introduction

Apply Docker sandbox network policies to `ralph-sandbox.ps1` so the AI agent sandbox runs in denylist mode — all network traffic blocked by default, with explicit allowances for required hosts only. This hardens the sandbox against unintended network access (e.g., the agent calling arbitrary APIs or exfiltrating data).

## Goals

- Lock down sandbox networking to only the hosts Ralph needs
- Prevent the agent from making arbitrary outbound requests
- Keep the policy maintainable and visible in the script (inline flags, not a separate file)

## User Stories

### US-001: Apply denylist network policy to sandbox

**Description:** As a developer running Ralph, I want the sandbox to block all outbound traffic by default and only allow known-good hosts, so the agent can't reach arbitrary endpoints.

**Acceptance Criteria:**

- [ ] `docker sandbox network proxy` is called with `--policy deny` before Claude runs
- [ ] The following hosts are explicitly allowed:
  - GitHub: `github.com`, `*.github.com`, `*.githubusercontent.com`
  - NuGet (public): `*.nuget.org`, `api.nuget.org`
  - NuGet (GitHub Packages): `nuget.pkg.github.com`
  - Docker registries: `*.docker.io`, `*.docker.com`
  - Anthropic API: `*.anthropic.com`, `api.anthropic.com`
- [ ] The policy is applied once before the iteration loop, not on every iteration
- [ ] If the sandbox doesn't exist yet, it is created before the policy is applied
- [ ] Script still works end-to-end (sandbox starts, Claude runs, output is streamed)

### US-002: Handle policy application failures gracefully

**Description:** As a developer, I want the script to fail fast if the network policy can't be applied, so I don't waste an iteration with broken networking.

**Acceptance Criteria:**

- [ ] If `docker sandbox network proxy` returns a non-zero exit code, the script logs an error and exits
- [ ] The error message indicates what went wrong (includes the command output)

### US-003: Document bypass escape hatch

**Description:** As a developer, if I hit SSL/certificate errors at runtime, I need to know how to add bypass rules without re-reading the Docker docs.

**Acceptance Criteria:**

- [ ] A comment block in the script explains `--bypass-host` and when to use it
- [ ] Includes an example of adding a bypass rule for a host

## Functional Requirements

- FR-1: Before the iteration loop, ensure the sandbox exists (create it if needed)
- FR-2: Run `docker sandbox network proxy <sandbox-name> --policy deny` with `--allow-host` flags for each required host
- FR-3: If the proxy command fails, log the error and exit with code 1
- FR-4: The iteration loop must not re-apply the policy each iteration
- FR-5: Add inline comments documenting the bypass escape hatch

## Non-Goals

- Not updating `ralph-sandbox.sh` (bash script) — PS1 only
- No JSON policy file — inline flags only
- No bypass rules initially — add only if SSL issues arise at runtime
- No changes to the Dockerfile or sandbox template
- No changes to the iteration loop logic or Claude invocation

## Technical Considerations

- **Sandbox lifecycle:** `docker sandbox create` exists as a standalone command (separate from `run`). Use `docker sandbox create --name <name> --template <image> claude .` to create the sandbox, then `docker sandbox network proxy` to apply the policy, then `docker sandbox run` to execute Claude. The sandbox name is `claude-$((Get-Item $RepoRoot).Name)` (line 237 of current script).
- **Policy persistence:** Policies persist across sandbox restarts — stored at `~/.docker/sandboxes/vm/<name>/proxy-config.json`. Once applied, the policy survives sandbox stop/start. However, re-applying on each script run is harmless (idempotent) and ensures the policy is always correct.
- **Recommended flow:** Check if sandbox exists → if not, `docker sandbox create` with `--template` → apply network policy → enter iteration loop with `docker sandbox run` (no `--template` needed since sandbox already exists).
- **Host patterns:** `*.github.com` does NOT match `github.com` per Docker docs — both must be listed separately. Same for other root domains.

## Testing Strategy

- **Manual testing:** Run `ralph-sandbox.ps1` end-to-end and verify:
  1. Sandbox creates successfully
  2. Network policy is applied (check with `docker sandbox network proxy <name>` to view current policy)
  3. Claude can authenticate (Anthropic API reachable)
  4. Git operations work (push/pull to GitHub)
  5. NuGet restore works (public + GitHub feeds)
  6. Arbitrary hosts are blocked (e.g., `curl https://example.com` from inside sandbox should fail)
- **No automated tests** — this is a shell script, not .NET code

## Bypass Rules (Escape Hatch)

If SSL/certificate errors occur at runtime, Docker's network proxy does TLS interception which can conflict with certificate pinning or cause trust issues. Fix by adding `--bypass-host <pattern>` flags to the `docker sandbox network proxy` command. This tunnels traffic directly without decryption.

Common candidates if issues arise:
- `--bypass-host nuget.pkg.github.com` (GitHub Packages auth)
- `--bypass-host api.anthropic.com` (Claude auth tokens)

## Success Metrics

- Sandbox boots and Ralph completes iterations without network errors
- Arbitrary outbound requests from the sandbox are blocked
- No increase in iteration startup time (policy application should be <2s)

## Open Questions

None — all resolved.
