---
name: adr
description: "Create an Architecture Decision Record (ADR) with structured options analysis. Use when documenting architectural decisions, technical trade-offs, or design choices. Triggers on: create adr, new adr, architecture decision, document decision, adr for."
license: MIT
---

# ADR Scaffolder

Create Architecture Decision Records following the team's established format with structured options analysis, balanced pros/cons, and clear consequences.

---

## The Job

1. Explore the codebase and set up numbering
2. Gather decision context from the user (or propose when asked)
3. Draft the ADR in conversation, iterate until approved
4. Write the file and update the README index

**Important:** Never write the ADR file until the user approves the draft.

---

## Step 1: Explore and Setup

1. **Scan `docs/adr/`** for existing ADR files. Determine the next sequence number (3-digit, zero-padded: `001`, `002`, `003`...). If the directory doesn't exist, ask permission to create it.
2. **Read `CLAUDE.md`** — understand architecture, patterns, conventions, and constraints that may influence the decision.
3. **Read 1-2 existing ADRs** to calibrate tone and depth. Check if any prior ADRs relate to or constrain the new decision.
4. **Search for related code** based on the ADR topic — existing implementations, interfaces, configurations, and tests that touch the decision area. Use Glob and Grep.
5. **Share key findings** with the user when presenting questions. An ADR that ignores existing patterns will propose options that don't fit the codebase.

---

## Step 2: Gather Information

Ask the user these 4 questions **all at once**. For each, the user can answer directly or say **"propose"** to have you draft it from codebase context.

```
To create this ADR, I need a few things. Answer each, or say "propose" and I'll draft it:

1. **Context** — What problem are we solving? What's the current state and why does a decision need to be made?

2. **Options** — What approaches are we considering? (At least 2. I'll document pros/cons for each.)

3. **Decision** — Which option do you prefer and why? Any implementation details or scope boundaries?

4. **Consequences** — What are the positive and negative impacts of this decision?
```

When the user says "propose", use your codebase findings from Step 1 to generate that section. Present proposals for confirmation before proceeding.

---

## Step 3: Draft and Review

Present the full ADR as a markdown code block. Iterate until the user approves.

### Template

~~~markdown
# ADR-{NNN}: {Title}

## Table of Contents

- [Status](#status)
- [Context](#context)
- [Decision](#decision)
- [Consequences](#consequences)
- [Alternatives Considered](#alternatives-considered)
- [References](#references)

## Status

Proposed | Date: {YYYY-MM-DD}

## Context

{Problem statement. Current state of the system. Why a decision is needed.
Include constraints, business rules, or technical limitations that bound the decision.}

## Decision

{State the chosen approach clearly. Explain WHY it was selected over alternatives.
Include implementation details and code examples only when they clarify the design.}

## Consequences

### Positive

- {Benefit 1 — with brief explanation of impact}
- {Benefit 2}

### Negative

- {Trade-off 1 — with brief explanation and any mitigation}
- {Trade-off 2}

## Alternatives Considered

### {Alternative 1 Name}

{Description of the approach.}

**Pros:**
- {Advantage 1}
- {Advantage 2}

**Cons / Why not:**
- {Disadvantage 1}
- {Disadvantage 2}

### {Alternative 2 Name}

{Description of the approach.}

**Pros:**
- {Advantage 1}
- {Advantage 2}

**Cons / Why not:**
- {Disadvantage 1}
- {Disadvantage 2}

## References

- Related ADRs: {[ADR-NNN: Title](NNN-slug.md) — brief description of relationship, if any}
- External: {links to relevant docs, articles, RFCs, or standards that informed the decision}
~~~

### Rules

- **Title**: Describes the decision space, not the conclusion (e.g., "Document Storage Strategy" not "Use Blob Storage")
- **Table of Contents**: Always include with anchor links matching H2 headings
- **Status**: Always `Proposed` for new ADRs. Lifecycle: `Proposed` -> `Accepted` -> `Deprecated` | `Superseded by ADR-NNN`
- **Alternatives**: Minimum 2, each with at least 2 pros and cons/why-not. These are the rejected options — explain why they lost.
- **Date**: Use today's date in `YYYY-MM-DD` format on the Status line.
- **Consequences**: Be honest — don't minimise negatives. Include mitigation for significant trade-offs.
- **References**: Link related ADRs and external docs. Omit the section if there are genuinely none.
- **Immutability**: Accepted ADRs are immutable. To change a decision, create a new ADR that supersedes the old one (`Superseded by ADR-NNN`) — don't edit the original.

After presenting the draft, ask:

```
Review the draft and let me know:
- **Approve** — I'll write it to `docs/adr/{NNN}-{slug}.md` and update the README
- **Change** — tell me what to adjust
```

---

## Step 4: Write Files

### ADR File

Write to `docs/adr/{NNN}-{kebab-case-slug}.md` (e.g., `002-document-storage-strategy.md`). No YAML frontmatter.

### README Index

Create or update `docs/adr/README.md` with a table of all ADRs:

```markdown
# Architecture Decision Records

| # | Title | Status | Date |
|---|-------|--------|------|
| [ADR-001](001-allocation-confirmation-screen.md) | Transaction Confirmation Screen | Under review | 2025-11-10 |
| [ADR-002](002-document-storage-service.md) | Document Storage Service | Under review | 2025-12-03 |
| [ADR-003](003-new-decision.md) | New Decision Title | Proposed | 2026-03-24 |
```

- If `README.md` doesn't exist, create it with rows for every existing ADR (scan filenames and read Status from each).
- If it exists, append the new row. Keep rows sorted by number.

### Next Steps

After writing, suggest:

```
ADR written to `docs/adr/{NNN}-{slug}.md` and README updated.

Next steps:
- Commit: `docs: add ADR-{NNN} for {title}`
- Create a PR for team review
- Once approved, update Status from "Proposed" to "Accepted"
```

---

## Quality Checklist (internal — do not show to user)

Before presenting the draft, verify:

- [ ] At least 2 alternatives with pros and cons/why-not
- [ ] Decision explains WHY, not just WHAT
- [ ] Consequences are honest — negatives aren't minimised
- [ ] Table of contents anchors match H2 headings
- [ ] Status is "Proposed"
- [ ] Title describes the decision space, not the conclusion
