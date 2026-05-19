#!/bin/bash
# PostToolUse hook: after git push or gh pr create on a branch with an open PR,
# hard-fail the tool result so Claude must invoke /pr-build-doctor before continuing.

set -e

. "$(dirname "$0")/../lib/tool-input/parse.sh"
tool_input_load

cmd=$(ti_get command)

# Only fire on git push or gh pr create. Skip --no-verify discriminator.
if ! printf '%s' "$cmd" | grep -qE '(git +push|gh +pr +create)'; then
    exit 0
fi

# Find PR for current branch (gh pr view defaults to current branch).
PR=$(gh pr view --json number -q .number 2>/dev/null || true)
if [ -z "$PR" ]; then
    exit 0
fi

# Hard-fail: stderr message + exit 2 makes Claude treat this as a tool error
# and forces it to address the message before doing anything else.
cat >&2 <<MSG
ENFORCEMENT: A push or PR-create just landed on a branch with open PR #$PR.

You MUST invoke the /pr-build-doctor skill via the Skill tool right now, with arg "$PR", before any further action.

Memory rule (workflow_pr.md, "Auto-run /pr-build-doctor") requires it. Do not ask, do not skip, do not defer.
MSG
exit 2
