---
name: risk
description: "Assess the risk level of a PR or change. Use when evaluating changes before deployment, reviewing PRs, or determining required mitigations. Triggers on: assess risk, risk assessment, evaluate pr risk, what's the risk of this pr."
license: MIT
---

# PR Risk Assessment

Evaluate changes across four dimensions to determine risk level and required mitigations.

---

## The Job

1. Gather context about the change (PR, branch diff, or description)
2. Ask the engineer assessment questions for each dimension
3. Calculate risk score based on "Yes" answers
4. Update PR description with risk assessment (if PR exists)
5. Output risk category and recommended mitigations

**Important:** Default to caution - if unsure, choose "Yes".

---

## Step 1: Gather Context

Before asking questions, understand what's changing:

- If a PR URL is provided, fetch the PR details
- If on a feature branch, run `git diff main...HEAD` (or appropriate base branch)
- If neither, ask the engineer to describe the change

---

## Step 2: Assessment Questions

Ask all questions using the AskUserQuestion tool. Group by dimension.

### Dimension A - Customer & Business Impact

```
A1. Could this change affect customer transaction flow, money movement, or user experience?
A2. Could incorrect behaviour cause regulatory or reputational harm?
```

### Dimension B - System & Architectural Impact

```
B1. Does this change touch a critical path (payments, onboarding, authentication, etc.)?
B2. Does it modify shared libraries, cross-cutting infrastructure, or highly coupled areas?
```

### Dimension C - Data & Security Impact

```
C1. Does it change how data is persisted, transformed, or exposed?
C2. Does it affect access control, security boundaries, or data subject rights?
```

### Dimension D - Operational / Delivery Impact

```
D1. Could this change cause deploy or rollback complexity?
D2. Could it degrade performance or reliability?
```

### Question Format

Use AskUserQuestion with Yes/No options for each dimension:

```
Dimension A - Customer & Business Impact

A1. Could this change affect customer transaction flow, money movement, or user experience?
   - Yes
   - No

A2. Could incorrect behaviour cause regulatory or reputational harm?
   - Yes
   - No
```

Include a brief reason field where the engineer can explain their answer.

---

## Step 3: Calculate Risk Score

Count total "Yes" answers across all 8 questions:

| Yes Count | Risk Level |
|-----------|------------|
| 0-1       | LOW        |
| 2         | MEDIUM     |
| 3-4       | HIGH       |
| 5+        | CRITICAL   |

---

## Step 4: Update PR with Risk Assessment

After calculating the risk score, **always** update the PR:

1. Check for existing PR: `gh pr view --json number,body`
2. If PR exists, append the risk assessment to the existing body using `gh pr edit`
3. Preserve existing PR description content, add risk section at the end
4. If no PR exists, just output the assessment for the user

**Example command:**
```bash
gh pr edit --body "$(cat <<'EOF'
[existing body content]

## Risk Assessment
[assessment content]
EOF
)"
```

---

## Step 5: Output Risk Assessment

Generate the assessment in this format:

```markdown
## Risk Assessment

**Risk Category:** [HIGH / MEDIUM / LOW]

### Assessment Summary

| Dimension | Result | Notes |
|-----------|--------|-------|
| A. Customer/Business Impact | Yes/No | [brief reason] |
| B. System/Architectural Impact | Yes/No | [brief reason] |
| C. Data/Security Impact | Yes/No | [brief reason] |
| D. Operational/Delivery Impact | Yes/No | [brief reason] |

**Total Yes Answers:** X/8

### Required Mitigations

[List based on risk level - see below]

### Reviewer Notes

[Any additional context or concerns]
```

---

## Mitigations by Risk Level

### LOW Risk (0-1 Yes)

- Standard automated tests (unit, integration)
- Normal peer review
- Standard deployment

**Examples:** UI copy change, logging update, non-critical refactor

### MEDIUM Risk (2 Yes)

- Pairing or extended peer review
- Automated tests + targeted manual testing
- Optional feature flag or staged rollout
- Observability checks (logs/metrics added)

**Examples:** Change in moderately important service path, minor schema change, new endpoint behind a flag

### HIGH Risk (3-4 Yes)

**Mandatory:**
- Feature flag OR dark launch
- Manual QA + UAT
- Runbook or rollback plan
- Targeted monitoring dashboards
- Cross-team review (if dependencies exist)
- Canary or progressive delivery

**Examples:** Payment flow change, data migration, authentication logic, changes in critical or brittle parts

### CRITICAL Risk (5+ Yes)

**All HIGH mitigations PLUS:**
- Architecture review
- Explicit sign-off from tech lead
- Extended monitoring period post-deploy
- Consider breaking into smaller changes

---

## PR Description Template

If adding to a PR, use this format:

```markdown
## Risk Assessment

**Risk Category:** [HIGH / MEDIUM / LOW]

| Dimension | Result | Reason |
|-----------|--------|--------|
| Customer/Business | Yes/No | [reason] |
| System/Architecture | Yes/No | [reason] |
| Data/Security | Yes/No | [reason] |
| Operational/Delivery | Yes/No | [reason] |

**Mitigations:**
- [List applied mitigations]
```

---

## Checklist

Before completing assessment:

- [ ] Understood the scope of the change
- [ ] Asked all 8 assessment questions
- [ ] Counted Yes answers correctly
- [ ] Assigned appropriate risk level
- [ ] Listed required mitigations for that level
- [ ] Updated PR with risk assessment (if PR exists)
- [ ] Output formatted assessment
