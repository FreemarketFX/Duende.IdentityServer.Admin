#!/bin/bash
# PreToolUse hook for AskUserQuestion: hard-fail if the question batch contains
# AI-tells suggesting the answer is already determined by CLAUDE.md, ticket,
# memory, or the model's own "(Recommended)" tag. Forces revision before send.

set -e

input=$(cat)

# Heuristic: any option label saying "(Recommended)" is the canonical AI-tell of
# "I'm asking but I already know what to do". Other red flags: explicit name-drops
# of CLAUDE.md / ticket / spec / rule / convention in option descriptions.
problematic=$(printf '%s' "$input" \
    | grep -cEi '\(recommended\)|matches? .{0,15}(claude\.md|ticket|spec|prd|rule|convention)|per the (rule|spec|ticket|convention|prd)|already (decided|in (claude\.md|the prd|the ticket)|covered by)' \
    || true)

if [ "$problematic" -gt 0 ]; then
    cat >&2 <<'MSG'
ENFORCEMENT (AskUserQuestion gate): This batch contains markers suggesting at least one question has an answer already determined by CLAUDE.md, ticket, PRD, memory, or your own recommendation.

REVISE before re-issuing. Checklist:

1. For each question, is the answer determined by:
   - CLAUDE.md or repo conventions?
   - ticket.txt or the existing PRD?
   - Memory rules?
   - Your own "(Recommended)" choice that just restates a written rule?
   If YES => REMOVE that question and apply the rule directly.

2. Bundling rule-decided questions with genuine ones poisons the whole batch. Split them.

3. For "what's the actual data" lookups (lists, IDs, config values), search the codebase / org first via `gh search code` or Grep. Only ask if the search returns nothing usable.

See ~/.claude/projects/.../memory/feedback_dont_ask_when_rules_decide.md.
MSG
    exit 2
fi

exit 0
