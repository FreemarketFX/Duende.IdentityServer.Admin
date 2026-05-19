#!/bin/bash
# PreToolUse on Bash. Block `gh pr create` when the branch's commits (vs base)
# contain files under tasks/current/. CLAUDE.md PR Hygiene: archive ralph
# artifacts via /post-ralph before opening the PR.
#
# Intentionally does NOT gate `git add` / `git commit` — ralph commits prd.json
# and progress.txt iteratively during a run, and blocking those breaks the loop.
# The only thing that must not happen is shipping those files in a PR diff.

set -e

. "$(dirname "$0")/../lib/tool-input/parse.sh"
tool_input_load

cmd=$(ti_get command)

# Only fire on `gh pr create`.
printf '%s' "$cmd" | grep -qE '\bgh +pr +create\b' || exit 0

# Determine base branch (default main, fall back to master).
base=main
git rev-parse --verify "$base" >/dev/null 2>&1 || base=master
git rev-parse --verify "$base" >/dev/null 2>&1 || exit 0

# Files added/modified on this branch but not on base.
offenders=$(git diff --name-only "$base"...HEAD 2>/dev/null | grep -E '^tasks/current/' || true)

[ -z "$offenders" ] && exit 0

cat >&2 <<MSG
ENFORCEMENT (no-tasks-current-in-pr): this branch's commits include files under \`tasks/current/\`:

$offenders

CLAUDE.md PR Hygiene: NEVER ship tasks/current/ in a PR — prd.json and progress.txt cause merge conflicts and pollute the diff.

Run the /freemarket-claude-skills:post-ralph skill to archive the run (moves files under tasks/archived/<date>/), commit the archive, then re-run \`gh pr create\`.
MSG
exit 2
