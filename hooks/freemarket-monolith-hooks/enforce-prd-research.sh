#!/bin/bash
# PreToolUse on Write/Edit for PRD/spec/ADR markdown: hard-fail when the new
# content contains lazy "Open Question" markers without proof of codebase
# research. Forces grep/gh-search before any deferral is allowed in writing.

set -e

. "$(dirname "$0")/../lib/tool-input/parse.sh"
tool_input_load

file_path=$(ti_get file_path)

# Limit to PRD/spec/ADR-style files. Add more globs as the repo grows.
case "$file_path" in
    */tasks/prd-*.md|*/tasks/spec-*.md|*/docs/adr/*.md|*/docs/architecture/*.md)
        ;;
    *)
        exit 0
        ;;
esac

content=$(ti_content)

# Patterns that flag unresolved deferrals.
lazy='defer to (ralph|reviewer|review|the reviewer|product|qa|engineering|whoever|<author>)|to be confirmed|to be decided|confirm with [a-z]|pending [a-z]+( at)? review|\btbd\b|t\.b\.d\.|need to (confirm|check)|not sure (if|whether)|sticky issue'

# Patterns that count as research evidence.
research='searched: |precedent: |no match in (codebase|repo|org)|gh search code|grep .{0,40}(returned|found|no match)|verified (against|via) (existing|codebase|repo)|matches existing pattern at|established by [^\.\n]{0,60}:[0-9]+'

if printf '%s' "$content" | grep -qiE "$lazy"; then
    if printf '%s' "$content" | grep -qiE "$research"; then
        exit 0
    fi
    cat >&2 <<'MSG'
ENFORCEMENT (PRD/spec write gate): The content you're writing contains lazy-deferral phrasing ("Defer to reviewer", "TBD", "pending X", "confirm with Y", "to be decided", "not sure whether...", "sticky issue") WITHOUT proof you researched the codebase first.

REVISE before re-writing. For every deferred item:

1. Search first. Run at least one of:
   - Grep over `src/` and `test/` for the symbol/concept
   - `gh search code --owner FreemarketFX <pattern>`
   - Read ticket.txt and any linked PRDs in `tasks/`
   - Scan existing tests for the pattern

2. If precedent exists => RESOLVE inline. Cite it with one of:
   - `Precedent: path/to/file.cs:42`
   - `Established by <feature> across N call sites: <files>`
   - `Matches existing pattern at <file:line>`

3. If genuinely no precedent => annotate the search inline:
   - `Searched: <patterns>; no match in codebase.`
   - That justifies the deferral.

4. The `Open Questions` heading is fine; unjustified items under it are not. "Defer to reviewer" without evidence of research is the exact failure mode this hook exists to catch.

See feedback_dont_ask_when_rules_decide.md.
MSG
    exit 2
fi

exit 0
