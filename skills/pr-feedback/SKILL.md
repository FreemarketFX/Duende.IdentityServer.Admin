---
name: pr-feedback
description: "Review PR comments and update PRD with required changes for Ralph. Use after receiving PR feedback. Triggers on: pr feedback, review pr comments, update prd from pr, address pr feedback."
license: MIT
---

# PR Feedback to PRD

Reviews PR comments, extracts actionable feedback, and adds new user stories to the PRD for Ralph to implement.

---

## The Job

1. Get PR number (from args or current branch)
2. Fetch unresolved PR review comments via `gh api`
3. Analyze comments for actionable changes
4. Add new user stories to `prd.json`
5. Optionally run Ralph loop

---

## Step 1: Identify the PR

If PR number provided as argument, use it. Otherwise:

```bash
# Get PR for current branch
gh pr view --json number -q '.number'
```

If no PR exists for current branch, ask user for PR number.

---

## Step 2: Fetch PR Comments

```bash
# Get unresolved review comments (inline code comments)
gh api repos/{owner}/{repo}/pulls/{pr_number}/comments

# Get unresolved issue-style comments (general discussion)
gh api repos/{owner}/{repo}/issues/{pr_number}/comments
```
Filter out resolved comments.

Parse the JSON response. Key fields:
- `body`: The comment text
- `path`: File being commented on (for review comments)
- `line`: Line number (for review comments)
- `user.login`: Who wrote the comment

---

## Step 3: Analyze Comments

For each comment, determine if it's:

**Actionable** (add to PRD):
- "This should also check X"
- "Add validation for Y"
- "The test should verify Z"
- "Missing error handling for..."
- "Need to update the UI to..."

**Not actionable** (skip):
- Questions ("Why did you...?")
- Praise ("Looks good!")
- Nitpicks already addressed
- Discussion/clarification

---

## Step 4: Create User Stories

For each actionable comment, create a new user story:

```json
{
  "id": "US-XXX",
  "title": "[Brief description of the fix]",
  "description": "PR feedback: [summarized requirement]",
  "acceptanceCriteria": [
    "[Specific verifiable criterion from comment]",
    "All tests pass"
  ],
  "priority": [next available],
  "passes": false,
  "notes": "PR comment by @{user}: {original comment}"
}
```

### Story Title Guidelines
- Start with verb: "Fix", "Add", "Update", "Verify"
- Be specific: "Fix content test to verify actual values" not "Fix test"
- Keep under 60 chars

### Acceptance Criteria Guidelines
- Extract the specific requirement from the comment
- Make it verifiable (not vague)
- Include "All tests pass" or "Typecheck passes"

---

## Step 5: Update prd.json

1. Read current `tasks/current/prd.json` (the Ralph PRD location — NOT `scripts/ralph/prd.json`)
2. Find highest existing story ID (e.g., US-004)
3. Add new stories with sequential IDs (US-005, US-006, etc.)
4. Set priority to continue from last story
5. Write updated prd.json

---

## Step 6: Summary

Output a summary:
```
## PR Feedback Summary

**PR #25**: feat(FMFX-14490): Add email integration tests

### Comments Reviewed: 3
### New Stories Added: 1

| ID | Title | From |
|----|-------|------|
| US-005 | Fix content test to verify actual values | @Jonny-Freemarket |

### Skipped (not actionable):
- "Looks good!" - praise
- "Why use WireMock?" - question (no change needed)

Ready to run Ralph? The new stories are in `tasks/current/prd.json`.
```

---

## Step 7: Optionally Run Ralph

Ask user if they want to run Ralph now to implement the changes:

```
Would you like me to run Ralph to implement these changes?
A. Yes, run Ralph now
B. No, I'll run it manually later
```

If yes, execute the ralph script or inform user how to run it.

---

## Example

**PR Comment:**
> This test should be checking that the content matches what was sent for both plain/text and html/txt

**Generated Story:**
```json
{
  "id": "US-005",
  "title": "Fix content verification test to check actual values",
  "description": "PR feedback: test should verify content values match what was sent",
  "acceptanceCriteria": [
    "Test verifies HTML content matches event LoginLink value",
    "Test verifies plain-text content matches stripped LoginLink",
    "All tests pass"
  ],
  "priority": 5,
  "passes": false,
  "notes": "PR comment by @Jonny-Freemarket: This test should be checking that the content matches what was sent for both plain/text and html/txt"
}
```

---

## Edge Cases

### No actionable comments
If all comments are questions/praise:
```
No actionable feedback found in PR comments. Nothing to add to PRD.
```

### Multiple comments on same issue
Consolidate into single story if they're about the same thing.

### Comment already addressed
Check if a story already exists for the feedback (search by similar title/criteria). Skip if already present.

### PRD doesn't exist
If `prd.json` doesn't exist, inform user to create one first using `/prd` and `/ralph` skills.

---

## Checklist

Before updating prd.json:

- [ ] Fetched both review comments and issue comments
- [ ] Filtered to actionable feedback only
- [ ] Each new story is small (one iteration)
- [ ] Acceptance criteria are specific and verifiable
- [ ] Story IDs are sequential from existing max
- [ ] Original comment preserved in notes field
