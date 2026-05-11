---
name: handover
description: Compact the current conversation into handover-{description}.md in the OS temp dir — context, decisions, open questions, next steps, without duplicating PRDs/ADRs/code (referenced by path instead). Args name the file and curate the focus. Invoke on: "handover", "hand off to next session", "create a handover", "wrap up for next agent", "context for next session", or similar end-of-session phrases.
license: MIT
---

# Handover

Creates a tight, scannable handover document a fresh Claude session can read in under a minute. The goal is to capture only what isn't already recorded elsewhere — decisions made verbally, current in-progress state, and open questions — so the next agent doesn't waste time re-discovering context that already exists in the conversation.

## Step 1: Determine the description

Derive a short kebab-case description to use as the filename suffix:

- If the user passed args (e.g. `/handover write integration tests`), slugify them: `write-integration-tests`
- Otherwise, infer a brief label from the session topic (e.g. `payment-handler`, `auth-refactor`)

Construct the path:

- **Windows**: `$env:TEMP\handover-{description}.md`
- **macOS/Linux**: `/tmp/handover-{description}.md`

If a file already exists at that path, read it before overwriting — you may be updating a handover from earlier in the same session.

## Step 2: Gather current state

Before writing, pull:

- Current branch: `git branch --show-current`
- Git status summary: `git status --short` (staged/unstaged files only, not the diff)
- Any active PRD path (`tasks/current/prd.json` or `apps/*/tasks/current/prd.json`)

## Step 3: Synthesise the conversation

Review the conversation and extract only what a new agent needs.

**Include:**
- Decisions made this session that aren't yet in a commit, ADR, or PRD
- Current in-progress state (e.g. "handler written, tests not yet written")
- Blockers and unresolved questions
- Non-obvious constraints or gotchas discovered this session
- Next steps, prioritised toward the args focus if provided

**Exclude — reference by path instead:**
- PRD content → just note `tasks/current/prd.json`
- ADR content → just note the file path
- Code → file path + function/class name, no quoting
- CLAUDE.md rules — the next session loads them automatically
- Memory file content — the next session loads them automatically

The test: if a fresh agent opened the referenced file or read the commit history, would they find this information? If yes, don't repeat it — point to it.

## Step 4: Suggest skills

Based on the focus (or overall session state if no args), suggest 2–5 skills the next agent should consider. Include a one-line reason for each. Common pairings:

| Situation | Suggest |
|-----------|---------|
| About to implement a feature | `/feature`, `/bdd-test`, `/integration-test` |
| PR ready to raise | `/self-code-review`, `/risk` |
| Architectural decision needed | `/adr`, `/question-me` |
| Starting a Ralph run | `/prd`, `/ralph` |
| Build / CI failing | `/pr-build-doctor` |
| Ralph run just finished | `/post-ralph`, `/ralph-log-doctor` |

## Step 5: Write the document

Write the file using this structure. Omit any section that has nothing meaningful to say.

```markdown
# Handover — {description}

{if args provided:}
## Next Session Focus

{args, verbatim or lightly tidied}

## Current State

- **Branch**: `{branch}`
- **Uncommitted changes**: {summary from git status, or "none"}
{if PRD active:}
- **Active PRD**: `{path}`

## Context

{2–4 sentences: what this session was doing and why — no code quoting, no rule repetition}

## Decisions Made This Session

{bullets — only decisions not already in commits, ADRs, or PRDs}

## Open Questions / Blockers

{bullets — unresolved items the next session needs to address}

## References

{paths to PRDs, ADRs, key files, branches, or URLs the next session will need}

## Next Steps

{ordered list of concrete actions, shaped by focus if args provided}

## Suggested Skills

{bullets, each with a one-line reason}
```

## Step 6: Report to user

Print the full path to the handover file. Suggest the next session open it with:

```
Read the handover at {path} before starting.
```
