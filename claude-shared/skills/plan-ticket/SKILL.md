---
name: plan-ticket
description: Generate a Jira ticket (title, description, acceptance criteria) from the current Claude Code plan. Triggers on plan-anchored asks only — "turn plan into ticket", "ticket from plan", "ticket from this plan", "convert plan to ticket", "generate acceptance criteria from plan". Do NOT use for generic ticket creation without a plan in scope (use `/prd` or `/jira-csv` instead).
license: MIT
---

# Plan to Ticket

Generate a structured Jira ticket from the current plan in the conversation.

## Finding the Plan

The plan is in the current conversation context. Read the active plan — it contains the
implementation steps, scope decisions, and technical details you need.

If no plan exists in the conversation, tell the user and ask them to create one first or
describe what they want a ticket for.

## Output Format

Output a single markdown block formatted for Jira:

```
h2. {Concise ticket title — action-oriented, under 80 chars}

h3. Description

{2-4 sentences summarising what this change does and why. Include enough context that
someone unfamiliar with the plan can understand the scope. Mention key technical
decisions if they constrain implementation.}

h3. Acceptance Criteria

{For each criterion, use Given/When/Then where the behaviour is naturally described as
a state transition or user interaction. Fall back to a simple checklist item when
Given/When/Then would be forced or awkward (e.g. "Code compiles with no warnings").}
```

*Example mix of acceptance criteria styles:*

```
* *Given* a user is on the dashboard, *When* they click refresh, *Then* the data reloads within 2 seconds
* CI pipeline passes with no new warnings
* Database migration is reversible
```

## Guidelines

- Derive acceptance criteria directly from the plan steps — each meaningful deliverable or behaviour should map to at least one criterion
- Keep criteria testable and specific — avoid vague language like "works correctly"
- If the plan mentions edge cases or error handling, include criteria for those
- Don't add scope beyond what the plan describes
- Omit implementation details from the description — focus on *what* and *why*, not *how*
- If the plan is large and would naturally split into multiple tickets, mention this to the user but still produce a single ticket unless asked otherwise
