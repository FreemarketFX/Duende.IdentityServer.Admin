# Skill Rule Injection

## Problem

Claude reads CLAUDE.md and MEMORY.md at conversation start but doesn't re-check them at the point where code is actually written. In long sessions (100k+ tokens), rules drop out of the attention window. This leads to repeated review feedback on things the rules already cover:
- Missing test assertions (RequiresSlot negative tests, error message verification)
- DisposeAsync not calling ResetRepository
- Stringly-typed values not converted to enums
- Collection assertions using Contain instead of BeEquivalentTo
- PUT endpoints missing SuccessWithVersion/SetETagHeader
- PRD stories not marked as passed
- Forward-declared endpoint names and HATEOAS links

## Eval Results

We ran generative evals comparing code output with vs without re-reading CLAUDE.md at the code-writing step. Three test cases, each run in both configurations:

| Eval | Task | With Rules | Without Rules |
|------|------|-----------|---------------|
| 1 | GET endpoint + tests | 7/7 | 7/7 |
| 2 | PUT endpoint + tests | 7/7 | 5/7 |
| 3 | Forward-declare trap | 6/6 | 6/6 |

**Key finding**: Simple patterns (BeEquivalentTo, Guid params, ResetRepository) stick regardless of token distance. Complex multi-step patterns (SetETagHeader call chain, functional permission test wiring) are where rules drop out of attention. The PUT endpoint eval showed 100% compliance with rule re-reading vs ~71% without.

**Limitation**: The eval's "without" configuration had rules ~3k tokens away. In real sessions, rules are 100k-200k tokens away. The eval understates the real gap.

## Fix

Add a "Load Project Rules" step to skills at the point where decisions happen. On 1M context enterprise tier, reading ~3k tokens of rules per skill invocation is negligible.

## Skills Updated

| Skill | Variant | Insertion Point | What Rules Inform |
|-------|---------|----------------|-------------------|
| `/feature` | A (generative) | Step 0, before Step 2 | Handler patterns, endpoint params, ETag handling, ProducesProblems |
| `/query` | A (generative) | Step 0, before Step 2 | HATEOAS naming, SuccessWithVersion, Guid params |
| `/bdd-test` | A (generative) | Step 0, before Step 2 | BeEquivalentTo, ResetRepository, negative permission tests, error messages |
| `/integration-test` | A (generative) | Step 0, before Step 2 | DTO reuse, assertion patterns, permission tests |
| `/post-ralph` | B (archival) | Substep 0, before Find PRD | PRD story verification (passes: true check) |
| `/self-code-review` | C (review) | Step 2.5, before Six Dimensions | Review checklist, severity floor (SHOULD FIX minimum for known rules) |

## The Step

Each variant instructs Claude to:
1. Use Glob to find the repo's CLAUDE.md (excluding claude-shared/, node_modules/, .claude/)
2. Read the "Common Review Feedback" section as a hard checklist
3. Read MEMORY.md and follow feedback-type memory links
4. Cross-reference generated code or review findings against the checklist

The step degrades gracefully: if no CLAUDE.md is found or the section doesn't exist, it skips silently.

## Objectivity: Run in New Agents

Skills that read CLAUDE.md and MEMORY.md for review/validation purposes can optionally be launched in a new agent (via the Agent tool) rather than run inline. This preserves objectivity -- the reviewing agent starts with a clean context and isn't biased by the decisions made during implementation.

Applies to: `/self-code-review` and any future review-oriented skills.

Does NOT apply to: `/post-ralph`, `/feature`, `/query`, `/bdd-test`, `/integration-test` and other generative skills where the context of the current conversation is needed.

## Not In Scope

- Hooks on every user message (too noisy)
- Hooks on git commit/push (too narrow, misses the generation phase)
- Modifying CLAUDE.md itself (the rules are already there)
