---
name: prd
description: "Generate a Product Requirements Document (PRD) for a new feature. Use when planning a feature, starting a new project, or when asked to create a PRD. Triggers on: create a prd, write prd for, plan this feature, requirements for, spec out."
allowed-tools: Glob, Grep, Read, AskUserQuestion, Agent, TaskCreate, TaskUpdate
license: MIT
---

# PRD Generator

Create detailed Product Requirements Documents that are clear, actionable, and suitable for implementation.

---

## Pre-requisite: Read the Project's CLAUDE.md

**Before generating any PRD content**, read the project's `CLAUDE.md` file in the repository root. This file defines:

- Architecture patterns (DDD, CQRS, vertical slices, domain events, Brighter/Darker)
- Testing standards (BDD specs, integration test requirements, test doubles policy, fixture patterns)
- Code style and conventions (naming, result types, endpoint patterns)
- Database strategy (Cosmos write store, SQL read store, domain event projections)

You **must** align the PRD's technical considerations, user stories, and acceptance criteria with these patterns. Do not invent testing or architectural approaches that contradict what CLAUDE.md prescribes.

---

## The Job

1. Receive a feature description from the user
2. **Read the project's `CLAUDE.md`** to understand architecture, testing, and code conventions
3. Ask 3-5 essential clarifying questions (with lettered options)
4. Generate a structured PRD based on answers, aligned with CLAUDE.md patterns
5. **Identify contradictions** between the ticket spec and the codebase — surface them visibly (see Open Questions format below), not buried in prose
6. Save to `tasks/prd-[feature-name].md`
7. **Present any Open Questions to the user and wait for explicit answers** before proceeding — do not proceed to `ralph` with unresolved questions
8. Stop — use the `ralph` skill separately to generate prd.json and commit everything

**Important:** Do NOT start implementing. Just create the PRD.

---

## Ticket Contradictions: Default to Minimum Viable Change

When `/ticket-validation` (or your own codebase reading) surfaces a contradiction between what the ticket spec describes and how the codebase actually works, **always default to the minimum viable change** — the path that delivers the goal with the lowest blast radius.

The classic failure mode: a ticket's dev notes describe a design that doesn't exist yet (e.g., "Profile is a value object with a Create factory" when it's actually a positional record). Following the ticket literally adds an architectural refactor on top of the feature work, expanding scope, increasing review burden, and risking a PR that's too large to merge safely.

**The rule:** if the simpler path achieves the stated goal, take it. Only include the architectural change if:
- The user explicitly asks for it after being shown the tradeoff, **or**
- The feature genuinely cannot be delivered without it

When you identify a contradiction, document it as an Open Question (see below) with both options and their tradeoffs — then stop and ask the user to choose before writing user stories.

---

## Step 1: Clarifying Questions

Ask only critical questions where the initial prompt is ambiguous. Focus on:

- **Problem/Goal:** What problem does this solve?
- **Core Functionality:** What are the key actions?
- **Scope/Boundaries:** What should it NOT do?
- **Success Criteria:** How do we know it's done?

### Format Questions Like This:

```
1. What is the primary goal of this feature?
   A. Improve user onboarding experience
   B. Increase user retention
   C. Reduce support burden
   D. Other: [please specify]

2. Who is the target user?
   A. New users only
   B. Existing users only
   C. All users
   D. Admin users only

3. What is the scope?
   A. Minimal viable version
   B. Full-featured implementation
   C. Just the backend/API
   D. Just the UI
```

This lets users respond with "1A, 2C, 3B" for quick iteration.

---

## Step 2: PRD Structure

Generate the PRD with these sections:

### 1. Introduction/Overview
Brief description of the feature and the problem it solves.

### 2. Goals
Specific, measurable objectives (bullet list).

### 3. User Stories
Each story needs:
- **Title:** Short descriptive name
- **Description:** "As a [user], I want [feature] so that [benefit]"
- **Acceptance Criteria:** Verifiable checklist of what "done" means

Each story should be small enough to implement in one focused session.

**Format:**
```markdown
### US-001: [Title]
**Description:** As a [user], I want [feature] so that [benefit].

**Acceptance Criteria:**
- [ ] Specific verifiable criterion
- [ ] Another criterion
- [ ] Build passes
- [ ] Associated tests pass
- [ ] **[UI stories only]** Verify in browser using dev-browser skill
```

**Important:**
- Acceptance criteria must be verifiable, not vague. "Works correctly" is bad. "Button shows confirmation dialog before deleting" is good.
- **Every story MUST include:** "Build passes" and "Associated tests pass" as acceptance criteria. This ensures code compiles and existing functionality isn't broken.
- **For any story with UI changes:** Always include "Verify in browser using dev-browser skill" as acceptance criteria. This ensures visual verification of frontend work.
- **Refactor stories as US-001:** If your first story (or any early story) is a refactor or infrastructure change rather than a direct feature addition, flag it before proceeding. Ask the user: "US-001 is a [refactor/restructure] — is this genuinely required to deliver the feature, or can we add the field/behaviour without it?" Only include it if the user confirms it's necessary. Refactor stories that sneak in as prerequisites are a common source of over-scoped PRs.

### 4. Functional Requirements
Numbered list of specific functionalities:
- "FR-1: The system must allow users to..."
- "FR-2: When a user clicks X, the system must..."

Be explicit and unambiguous.

### 5. Non-Goals (Out of Scope)
What this feature will NOT include. Critical for managing scope.

### 6. Design Considerations (Optional)
- UI/UX requirements
- Link to mockups if available
- Relevant existing components to reuse

### 7. Technical Considerations

This section is **required**, not optional. Base it on what you learned from the project's `CLAUDE.md`. Include:

- **Architecture:** Which bounded context does this belong to? What aggregates, domain events, and handlers are involved? Follow the DDD + CQRS patterns documented in CLAUDE.md.
- **Persistence:** Does this need Cosmos (write store), SQL projections (read store), or both? What domain event handlers update the read model?
- **Integration points:** Does this require Brighter events for cross-service messaging? Domain events for intra-aggregate side effects?
- **Known constraints or dependencies**

### 8. Testing Strategy

This section is **required**. Derive it from the project's `CLAUDE.md` Testing Standards. Include:

- **Unit tests (BDD):** Which domain logic and handlers need BDD specification tests? Use the Given/When/Then pattern with `Freemarket.Testing.Bdd.Specification` base class and partial class split (`.Specs.cs` + `.Steps.cs`). No mocking libraries — hand-written fakes/stubs/spies only.
- **Integration tests:** Which new endpoints require API integration tests? (All new endpoints need at minimum: happy path + 401 unauthorized). Use `ApiSpecification` base class with `ApiFixture`.
- **Architecture tests:** Are there new Brighter/Darker handlers that need architecture compliance tests?
- **Test doubles:** What fakes or spies are needed? Check for existing ones in `Tests.Shared` before creating new ones.
- **Fixtures:** Which collection fixtures apply (e.g., `UsersCollection`, `ClientsCollection`)? Does the test need Cosmos, SQL, or both via TestContainers?

### 9. Success Metrics
How will success be measured?
- "Reduce time to complete X by 50%"
- "Increase conversion rate by 10%"

### 10. Open Questions

Any unresolved questions or decisions that need the user's input before ralph runs.

**This section is a gate, not a footnote.** If there are any open questions — especially contradictions between the ticket spec and the codebase — do not silently default to an answer. After saving the PRD, present each open question to the user clearly and wait for an explicit answer before proceeding to `ralph` / `prd.json` generation.

Format contradictions prominently:

```
⚠️  CONTRADICTION: [brief description]
The ticket says: [what the ticket describes]
The codebase has: [what actually exists]
Option A (recommended): [simpler path — lower blast radius]
Option B: [follow ticket literally — why it's riskier]
Which do you want?
```

Do not bury contradictions in prose. One block per contradiction, shown before any implementation begins.

---

## Writing for Junior Developers

The PRD reader may be a junior developer or AI agent. Therefore:

- Be explicit and unambiguous
- Avoid jargon or explain it
- Provide enough detail to understand purpose and core logic
- Number requirements for easy reference
- Use concrete examples where helpful

---

## Output

- **Format:** Markdown (`.md`)
- **Location:** `tasks/`
- **Filename:** `prd-[feature-name].md` (kebab-case)

---

## Example PRD

```markdown
# PRD: Task Priority System

## Introduction

Add priority levels to tasks so users can focus on what matters most. Tasks can be marked as high, medium, or low priority, with visual indicators and filtering to help users manage their workload effectively.

## Goals

- Allow assigning priority (high/medium/low) to any task
- Provide clear visual differentiation between priority levels
- Enable filtering and sorting by priority
- Default new tasks to medium priority

## User Stories

### US-001: Add priority field to database
**Description:** As a developer, I need to store task priority so it persists across sessions.

**Acceptance Criteria:**
- [ ] Add priority column to tasks table: 'high' | 'medium' | 'low' (default 'medium')
- [ ] Generate and run migration successfully
- [ ] Build passes
- [ ] Associated tests pass

### US-002: Display priority indicator on task cards
**Description:** As a user, I want to see task priority at a glance so I know what needs attention first.

**Acceptance Criteria:**
- [ ] Each task card shows colored priority badge (red=high, yellow=medium, gray=low)
- [ ] Priority visible without hovering or clicking
- [ ] Build passes
- [ ] Associated tests pass
- [ ] Verify in browser using dev-browser skill

### US-003: Add priority selector to task edit
**Description:** As a user, I want to change a task's priority when editing it.

**Acceptance Criteria:**
- [ ] Priority dropdown in task edit modal
- [ ] Shows current priority as selected
- [ ] Saves immediately on selection change
- [ ] Build passes
- [ ] Associated tests pass
- [ ] Verify in browser using dev-browser skill

### US-004: Filter tasks by priority
**Description:** As a user, I want to filter the task list to see only high-priority items when I'm focused.

**Acceptance Criteria:**
- [ ] Filter dropdown with options: All | High | Medium | Low
- [ ] Filter persists in URL params
- [ ] Empty state message when no tasks match filter
- [ ] Build passes
- [ ] Associated tests pass
- [ ] Verify in browser using dev-browser skill

## Functional Requirements

- FR-1: Add `priority` field to tasks table ('high' | 'medium' | 'low', default 'medium')
- FR-2: Display colored priority badge on each task card
- FR-3: Include priority selector in task edit modal
- FR-4: Add priority filter dropdown to task list header
- FR-5: Sort by priority within each status column (high to medium to low)

## Non-Goals

- No priority-based notifications or reminders
- No automatic priority assignment based on due date
- No priority inheritance for subtasks

## Technical Considerations

- Reuse existing badge component with color variants
- Filter state managed via URL search params
- Priority stored in database, not computed

## Success Metrics

- Users can change priority in under 2 clicks
- High-priority tasks immediately visible at top of lists
- No regression in task list performance

## Open Questions

- Should priority affect task ordering within a column?
- Should we add keyboard shortcuts for priority changes?
```

---

## Checklist

- [ ] Asked clarifying questions with lettered options
- [ ] Incorporated user's answers
- [ ] User stories are small and specific
- [ ] Every user story includes "Build passes" and "Associated tests pass" acceptance criteria
- [ ] Functional requirements are numbered and unambiguous
- [ ] Non-goals section defines clear boundaries
- [ ] Saved to `tasks/prd-[feature-name].md`
- [ ] **Do NOT commit or update prd.json/progress.txt** — use the `ralph` skill for that
