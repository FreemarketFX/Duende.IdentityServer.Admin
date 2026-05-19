#!/usr/bin/env bash
# Block any Bash command that submits an APPROVE review to a GitHub PR.
# Runs as a PreToolUse hook on Bash; reads the tool input JSON from stdin.
# See ~/.claude/projects/C--dev-Organisation/memory/workflow_pr.md.
#
# We extract the actual `command` field from the tool input rather than
# grepping the raw JSON envelope, so descriptive prose in unrelated commands
# (e.g. a git commit message that mentions "gh pr review --approve") does not
# trip the regex.

set -e

. "$(dirname "$0")/../lib/tool-input/parse.sh"
tool_input_load

cmd=$(ti_get command)

# Fail open: if we cannot recover a command string, do not block.
[ -z "$cmd" ] && exit 0

# Strip out the contents of any `-m "..."` / `-m '\''...'\''` argument before
# matching, so commit-message prose can never trip the regex. Also strip
# heredoc bodies (single tag and quoted-tag forms; iterates so multiple
# heredocs with different tags are all removed).
sanitized=$(printf '%s' "$cmd" | python -c '
import sys, re
src = sys.stdin.read()
src = re.sub(r"-m\s+\"(?:\\.|[^\"\\])*\"", "-m \"\"", src)
src = re.sub(r"-m\s+'\''(?:[^'\''])*'\''", "-m '\'''\''", src)
# Heredoc: <<TAG ... TAG  or  <<'\''TAG'\'' ... TAG. Allow A-Za-z_ in tag.
heredoc = re.compile(r"<<\s*'\''?([A-Za-z_][A-Za-z0-9_]*)'\''?.*?\n\1", re.DOTALL)
prev = None
while prev != src:
    prev = src
    src = heredoc.sub("<<EOF EOF", src, count=1)
print(src)
' 2>/dev/null)

# If sanitization failed (no python, etc.), fall back to the raw command.
[ -z "$sanitized" ] && sanitized="$cmd"

# 1. `gh pr review ... --approve` (or the short form `-a`).
#    Anchor at start-of-command-or-after-separator so this only matches when
#    the command itself invokes `gh pr review`, not when another command
#    merely contains the substring.
if printf '%s' "$sanitized" | grep -qE '(^|[[:space:];|&])gh[[:space:]]+pr[[:space:]]+review[[:space:]][^|&;]*(--approve|[[:space:]]-a([[:space:]]|$))'; then
    printf '{"continue":false,"stopReason":"Blocked: never approve PRs. Use inline comments via gh api reviews endpoint with event COMMENT and let the user submit. See memory/workflow_pr.md."}'
    exit 0
fi

# 2. `gh api ... reviews ...` whose payload sets event=APPROVE.
#    Match a `reviews` endpoint AND an explicit APPROVE event token (--field
#    event=APPROVE, -F event=APPROVE, JSON "event": "APPROVE", etc.). Looser
#    shapes (the word APPROVE elsewhere in the env) are intentionally allowed.
if printf '%s' "$sanitized" | grep -qE '(^|[[:space:];|&])gh[[:space:]]+api[[:space:]][^|&;]*reviews'; then
    if printf '%s' "$sanitized" | grep -qE '(--field|-F)[[:space:]]+event=APPROVE|"event"[[:space:]]*:[[:space:]]*"APPROVE"'; then
        printf '{"continue":false,"stopReason":"Blocked: never approve PRs. Use inline comments via gh api reviews endpoint with event COMMENT and let the user submit. See memory/workflow_pr.md."}'
        exit 0
    fi
fi

exit 0
