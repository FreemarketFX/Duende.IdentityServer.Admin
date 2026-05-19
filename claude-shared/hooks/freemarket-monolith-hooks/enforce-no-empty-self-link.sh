#!/bin/bash
# PreToolUse on Write/Edit for *.cs files. Hard-fail when the new content
# introduces an empty-string self-link sentinel:
#   new HateoasLink("self", string.Empty)
#   new HateoasLink("self", "")
# These bypass ToCreated() validation and produce a 201 with no Location header.
# Caught in PR #250 (FMFX-15818): CreateInvitation.Command.cs.

set -e

. "$(dirname "$0")/../lib/tool-input/parse.sh"
tool_input_load

file_path=$(ti_get file_path)

case "$file_path" in
    *.cs)
        ;;
    *)
        exit 0
        ;;
esac

content=$(ti_content)

hits=$(printf '%s' "$content" | python -c '
import sys, re
src = sys.stdin.read()
# Strip comments so prose / commented-out samples cannot trip the hook.
# We do NOT strip string literals because the rel="self" literal is part of
# the pattern itself; string-stripping would either erase it or force a less
# precise match.
src = re.sub(r"//[^\n]*", "", src)
src = re.sub(r"/\*.*?\*/", "", src, flags=re.DOTALL)

pat = re.compile(r"new\s+HateoasLink\s*\(\s*\"self\"\s*,\s*(string\.Empty|\"\")\s*\)")
if pat.search(src):
    print("yes")
')

if [ -n "$hits" ]; then
    cat >&2 <<MSG
ENFORCEMENT (no-empty-self-link): The new content in $file_path introduces an empty-string self-link sentinel:

    new HateoasLink("self", string.Empty)   ← banned
    new HateoasLink("self", "")             ← banned

This bypasses \`ToCreated()\` validation and yields a 201 with no Location header. A future reader cannot tell whether the empty string is intentional or a bug.

Acceptable alternatives:
  1. Use \`response.ToCreated()\` with a real route — preferred.
  2. If no GET-by-id endpoint exists yet, use \`new Created<T>(null!) { Content = response }\` (if the framework accepts it).

There is no comment-based bypass for this hook — comments are stripped before
matching. Land the GET-by-id endpoint (option 1) or use option 2.
MSG
    exit 2
fi

exit 0
