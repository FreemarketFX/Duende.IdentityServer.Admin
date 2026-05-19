---
name: ticket-validation
description: "Cross-references a work item with the codebase to surface requirement gaps in validation, permissions, invariants, events, contracts, persistence, and tests. Invoked by: ticket validation, requirement check, pre-prd review."
allowed-tools: Glob, Grep, Read, AskUserQuestion, Agent, TaskCreate, TaskUpdate
license: MIT
---

# Ticket Validation

Validate a work item (Jira ticket, feature brief, or description) against the codebase to surface gaps and missing requirements.

---

## The Job

1. Receive the work item (Jira URL, pasted description, or verbal brief)
2. Identify which bounded context(s) and features are affected
3. Explore the codebase for existing patterns, constraints, and related code
4. Assess the work item across validation dimensions
5. Output a gap analysis report with codebase evidence

**Important:** Do NOT create PRDs or implement anything. Just validate and report.

---

## Step 1: Receive the Work Item

### Auto-detect context

Before asking the user for anything, check for existing context:

1. **Check for `ticket.txt`** anywhere in the repo using `Glob("**/ticket.txt")`. Common locations include the repo root and `/scratch`. If found, read it and use it as the primary input. Do not ask the user to paste the ticket again.

2. **Search for tech specs** under `/docs` using `Glob("docs/**/*.md")`. Filter results for spec-like files (filenames containing `spec`, `techspec`, `technical`, or `requirements`). Exclude PRD files. Read any relevant tech spec for additional context on domain rules, data model, and architectural decisions that the ticket may reference or depend on.

3. **If `ticket.txt` was not found**, ask the user for the work item. Tech specs alone are supplementary context -- they don't describe the specific work item to validate.

### Accepted input formats

- **Jira URL** -- fetch with `gh` or ask user to paste the description
- **Pasted text** -- ticket description, acceptance criteria, feature brief
- **Verbal description** -- a spoken/typed summary of what needs building

### Extract and confirm

- **What** is being built (feature name, operation type)
- **Where** it lives (which bounded context: Users, Clients, etc.)
- **Why** it exists (business goal or problem being solved)

If any of these are unclear from the gathered context, ask the user before proceeding.

---

## Step 2: Explore the Codebase

Search the affected area(s) to understand what already exists:

1. **Find related features** — glob for existing feature folders in the target module
2. **Find the domain aggregate(s)** — read the aggregate class(es) that will be touched
3. **Find existing validators** — check what validation rules already exist for related commands
4. **Find existing permissions** — check `RolesAndPermissions` for relevant permission constants
5. **Find existing domain events** — check what events the aggregate already raises
6. **Find SQL projections** — check if read models / SQL views exist for the entity
7. **Find existing tests** — check for BDD specs and integration tests in the area

Build a mental model of:
- Current aggregate shape (properties, methods, invariants)
- Current validation rules in neighbouring features
- Current permission model
- Current domain events and side effects
- Current test coverage

---

## Step 3: Assess Across Validation Dimensions

Evaluate the work item against each dimension below. For each, determine whether the work item has a **genuine gap** — something not mentioned in the work item AND not already solved by established codebase patterns.

**Key rule:** If the work item doesn't mention something but the codebase already handles it by convention (e.g., all commands use `[LoadPermissions]`, all aggregates raise domain events on mutation), that is NOT a gap. The implementer will follow the existing pattern. Only report gaps where the work item is silent AND the codebase doesn't have an obvious pattern to follow.

### Dimension 1: Input Validation

Does the work item specify what input validation is needed?

- Required fields and their constraints (length, format, range)
- Enum values and their valid options
- Cross-field validation rules (e.g., "end date must be after start date")
- Uniqueness constraints (e.g., "email must be unique per tenant")
- Reference validation (e.g., "linked entity must exist")

**Codebase check:** Compare against validators in neighbouring features. If the codebase already has a clear validation pattern for similar fields (e.g., all Name fields use `MaximumLength(100)`), this is not a gap — the implementer will follow suit. Only flag if the work item introduces a field or constraint with no precedent in the codebase.

### Dimension 2: Authorization & Permissions

Does the work item specify who can perform this action?

- Which permission(s) are required
- Whether new permissions need to be created
- Whether permission checks differ by role or context
- Whether HATEOAS links need to be permission-aware

**Codebase check:** Look at `RolesAndPermissions` constants and `[LoadPermissions]` usage in related features. If a suitable permission already exists and the codebase consistently applies it, this is not a gap. Only flag if a new permission is needed or the work item requires a non-obvious permission model.

### Dimension 3: Domain Invariants & Business Rules

Does the work item specify the business rules the domain must enforce?

- State transition rules (e.g., "can only cancel an enabled account")
- Ownership/relationship rules (e.g., "only subaccounts can link legal entities")
- Computed or derived values
- Constraints that prevent invalid aggregate state

**Codebase check:** Read the target aggregate's existing methods. If the aggregate already enforces similar invariants (e.g., state transition checks), the implementer will follow the same pattern — not a gap. Only flag if the work item implies a business rule that has no analogue in the existing domain model and the correct behaviour is ambiguous.

### Dimension 4: Side Effects & Events

Does the work item account for what happens after the primary action?

- Domain events to raise (for SQL projection updates, notifications, etc.)
- Brighter events to publish (for cross-service messaging)
- Read model / SQL projection updates needed
- Cascading effects on related aggregates

**Codebase check:** Look at existing domain event handlers and Brighter event handlers in the module. If neighbouring features consistently raise domain events on similar mutations (e.g., all create/update operations raise an Upserted event), the implementer will follow suit — not a gap. Only flag if the work item has side effects that break from established patterns or require a new event type with unclear semantics.

### Dimension 5: API Contract & Response Handling

Does the work item specify the API shape?

- HTTP method and route
- Request/response DTOs
- Error responses (404, 409, 422 scenarios)
- HATEOAS resource links
- Pagination (if applicable)

**Codebase check:** Look at neighbouring endpoints for consistent patterns. If the codebase has a clear convention for similar endpoints (e.g., all POST endpoints return 201, all use `CommandResultHandler`), this is not a gap. Only flag if the work item implies an API shape that deviates from convention or has ambiguous requirements.

### Dimension 6: Data & Persistence

Does the work item address storage concerns?

- Cosmos document changes (new properties on aggregate)
- SQL migration needed (new columns, tables, views)
- Index requirements
- Data migration for existing records

**Codebase check:** Check the aggregate's Cosmos structure and any SQL views/tables. If the codebase already has a Cosmos + SQL projection pattern for this aggregate, new properties will follow the same flow — not a gap. Only flag if the work item requires a new table, a schema change with no precedent, or data migration for existing records.

### Dimension 7: Testing Requirements

Does the work item specify or imply test coverage?

- Unit tests for domain logic / business rules
- Integration tests for the endpoint (happy path + 401)
- Edge cases that need test coverage
- Existing tests that might break

**Codebase check:** Look at test coverage in the affected area. If the codebase has established BDD and integration test patterns for similar features, the implementer will follow them — not a gap. Only flag if the work item has edge cases or business rules that are non-obvious and need explicit test coverage called out.

---

## Step 4: Output Gap Analysis

Only report **genuine gaps** — things not covered by the work item AND not already solved by codebase convention. Omit dimensions where the codebase already has clear patterns that the implementer will follow.

If no gaps are found, say so clearly.

```markdown
## Work Item Validation Report

**Work Item:** [title or reference]
**Module:** [Users / Clients / etc.]
**Affected Aggregate(s):** [aggregate name(s)]

### Gaps Found

[Only list dimensions that have genuine gaps. Omit dimensions fully covered by the work item or by existing codebase patterns.]

#### [Dimension Name]
- **Gap:** [What's missing from the work item that the codebase can't answer either]
- **Why it matters:** [What could go wrong if this isn't clarified]
- **Recommendation:** [Specific suggestion or question to resolve]

### Covered by Codebase Convention

[Brief summary of what the codebase already handles, so the user knows these were checked but aren't concerns]

- [e.g., "Permissions: Account.Create permission already exists and all neighbouring commands use [LoadPermissions]"]
- [e.g., "Events: All account mutations raise AccountUpsertedDomainEvent — this feature will follow suit"]
```

---

## Checklist

Before completing validation:

- [ ] Understood what is being built and where it lives
- [ ] Explored the affected module's existing code
- [ ] Assessed all 7 dimensions
- [ ] Provided specific codebase evidence for each gap
- [ ] Listed existing patterns the feature should follow
