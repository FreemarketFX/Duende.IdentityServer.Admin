# PRD: Remove Telerik References

## Introduction

The project has moved away from Telerik NuGet packages. PR #43 (`add-telerik-auth`) added optional Telerik NuGet credential support to the Ralph sandbox. This feature is no longer needed and all Telerik references should be removed from active code, documentation, and configuration. Archive files are preserved as historical records.

## Goals

- Revert the code changes introduced by PR #43 in `ralph-sandbox.ps1`
- Remove Telerik network allow-host from the sandbox network policy
- Remove all Telerik-related environment variable handling (`TELERIK_TOKEN`)
- Clean up Telerik references in documentation (README, Dockerfile comment)
- Archive current Telerik task files and remove from `tasks/current/`
- Delete the now-obsolete Telerik PRD from `tasks/`

## User Stories

### US-001: Revert New-NuGetConfig to pre-Telerik state
**Description:** As a developer, I want the `New-NuGetConfig` function restored to its original signature and implementation (before PR #43), so there is no Telerik-related code in the NuGet config generation.

**Acceptance Criteria:**
- [ ] `New-NuGetConfig` signature is `($OutputPath, $GitHubPat)` — no `$TelerikPassword` parameter
- [ ] All Telerik conditional XML generation is removed (`$telerikSource`, `$telerikCredentials`, `$telerikMapping` variables)
- [ ] The `$safePat` XML-escaping of `$GitHubPat` (added in PR #43) is kept — this is a useful security improvement unrelated to Telerik
- [ ] The generated `nuget.config` template has no `$telerikSource`, `$telerikCredentials`, or `$telerikMapping` interpolations
- [ ] The `nuget.config` output contains only `nuget.org` and `GitHub-FreemarketFX` sources
- [ ] Build passes
- [ ] Associated tests pass

### US-002: Remove Telerik credential resolution block
**Description:** As a developer, I want the Telerik token environment variable check and interactive prompt removed from the main script flow.

**Acceptance Criteria:**
- [ ] The `$TelerikPassword` variable assignment block (~lines 376-383) is completely removed
- [ ] The `$env:TELERIK_TOKEN` check is removed
- [ ] The `Read-Host` prompt for Telerik NuGet token is removed
- [ ] The `-TelerikPassword $TelerikPassword` argument is removed from the `New-NuGetConfig` call
- [ ] Build passes
- [ ] Associated tests pass

### US-003: Remove Telerik from network allow-list
**Description:** As a developer, I want `nuget.telerik.com` removed from the sandbox network policy since no traffic should go to Telerik.

**Acceptance Criteria:**
- [ ] `--allow-host "nuget.telerik.com"` is removed from the network proxy command
- [ ] The bypass-host comment referencing `nuget.telerik.com` is removed from the escape-hatch comments
- [ ] Build passes
- [ ] Associated tests pass

### US-004: Clean up Telerik references in documentation
**Description:** As a developer, I want Telerik references removed from README.md and Dockerfile comments so documentation reflects current state.

**Acceptance Criteria:**
- [ ] `ralph-sandbox/README.md`: Remove `nuget.telerik.com` from the network allow-list documentation
- [ ] `ralph-sandbox/README.md`: Remove the `nuget.telerik.com` bypass-host example
- [ ] `ralph-sandbox/docker/Dockerfile.sandbox`: Update comment from "NuGet feeds (GitHub Packages, Telerik, etc.)" to "NuGet feeds (GitHub Packages)"
- [ ] Build passes
- [ ] Associated tests pass

### US-005: Clean up Telerik-related task files
**Description:** As a developer, I want Telerik-related PRD and task files archived or removed so the `tasks/` directory reflects current work.

**Acceptance Criteria:**
- [ ] `tasks/current/prd.json` and `tasks/current/progress.txt` are moved to `tasks/archive/telerik-nuget-auth-pr-feedback/`
- [ ] `tasks/prd-telerik-nuget-credentials.md` is deleted
- [ ] `tasks/archive/add-telerik-auth/` is left untouched (historical record)
- [ ] Build passes
- [ ] Associated tests pass

### US-006: Clean up Telerik references in sandbox network PRD
**Description:** As a developer, I want the network policies PRD updated to remove Telerik-specific references.

**Acceptance Criteria:**
- [ ] `tasks/prd-sandbox-network-policies.md`: Remove or update the line listing `nuget.telerik.com` as an allowed host
- [ ] `tasks/prd-sandbox-network-policies.md`: Remove Telerik from the NuGet restore test criteria
- [ ] Build passes
- [ ] Associated tests pass

## Functional Requirements

- FR-1: Revert `New-NuGetConfig` function in `ralph-sandbox.ps1` to its pre-PR#43 signature `($OutputPath, $GitHubPat)`, but **keep** the `$safePat = [System.Security.SecurityElement]::Escape($GitHubPat)` XML-escaping improvement
- FR-2: Remove the entire `$TelerikPassword` credential resolution block (env var check + interactive prompt)
- FR-3: Remove `-TelerikPassword $TelerikPassword` from the `New-NuGetConfig` call
- FR-4: Remove `--allow-host "nuget.telerik.com"` from the network proxy command
- FR-5: Remove `nuget.telerik.com` from bypass-host comments
- FR-6: Update `Dockerfile.sandbox` comment to remove Telerik mention
- FR-7: Update `README.md` to remove all Telerik host references
- FR-8: Archive `tasks/current/prd.json` and `tasks/current/progress.txt` to `tasks/archive/telerik-nuget-auth-pr-feedback/`
- FR-9: Delete `tasks/prd-telerik-nuget-credentials.md`
- FR-10: Update `tasks/prd-sandbox-network-policies.md` to remove Telerik references

## Non-Goals

- Do not modify `tasks/archive/add-telerik-auth/` — these are historical records
- Do not remove the XML-escaping of `$GitHubPat` (the `$safePat` variable) — this was a good security improvement introduced alongside the Telerik changes
- Do not remove the `post-ralph` keyword additions to plugin metadata — those were bundled in PR #43 but are unrelated to Telerik
- Do not modify `.claude-plugin/marketplace.json` or `.claude-plugin/plugin.json` version numbers

## Technical Considerations

- **Single primary file:** The main code change is in `ralph-sandbox/ralph-sandbox.ps1`
- **Keep XML-escaping:** PR #43 introduced `[System.Security.SecurityElement]::Escape()` for the GitHub PAT. This is a valuable safety improvement that should be preserved even though it was added in the same PR as Telerik support
- **Plugin metadata:** PR #43 also added `post-ralph` to keywords and bumped version to 1.7.0. These changes are unrelated to Telerik and should be kept
- **Line references may shift:** The line numbers referenced in this PRD are approximate — verify against the current file before editing

## Testing Strategy

- **Manual testing:** This is infrastructure code (PowerShell script) without a unit test framework
  1. Run `ralph-sandbox.ps1` — verify no Telerik prompt appears
  2. Verify generated `nuget.config` contains only `nuget.org` and `GitHub-FreemarketFX` sources
  3. Verify `$GitHubPat` is still XML-escaped in the generated config
  4. Verify network policy command no longer includes `nuget.telerik.com`
  5. Run a non-Telerik repo build in the sandbox — verify no regression

## Success Metrics

- Zero references to Telerik in active code files (outside `tasks/archive/`)
- Sandbox script runs without any Telerik-related prompts
- No regression in sandbox functionality for non-Telerik repos

## Open Questions

- None — scope is well-defined as a straightforward removal/revert
