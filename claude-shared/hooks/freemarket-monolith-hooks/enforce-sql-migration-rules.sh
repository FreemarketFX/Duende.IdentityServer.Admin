#!/bin/bash
# PreToolUse on Write/Edit for SQL migration scripts. Hard-fail if the new
# content introduces a CREATE TABLE without GRANT statements for the standard
# roles, or without an IsDeleted column.
#
# Source of truth: claude-shared/.claude/rules/sql.md and existing migrations
# (e.g. 0007-CreateResourceHierarchyView.sql).

set -e

. "$(dirname "$0")/../lib/tool-input/parse.sh"
tool_input_load

file_path=$(ti_get file_path)

case "$file_path" in
    */Migrations/Scripts/*.sql)
        ;;
    *)
        exit 0
        ;;
esac

content=$(ti_content)

# Find every CREATE TABLE declaration. Capture schema.tablename.
tables=$(printf '%s' "$content" | grep -oiE 'CREATE TABLE +\[[A-Za-z]+\]\.\[[A-Za-z]+\]' | sort -u || true)

if [ -z "$tables" ]; then
    exit 0
fi

violations=""

while IFS= read -r tline; do
    [ -z "$tline" ] && continue
    # Extract bare [Schema].[Name].
    bracketed=$(printf '%s' "$tline" | grep -oE '\[[A-Za-z]+\]\.\[[A-Za-z]+\]')
    name=$(printf '%s' "$bracketed" | sed -E 's/.*\.\[([A-Za-z]+)\]/\1/')

    # GRANT check: require at least 3 distinct GRANT statements referencing
    # the table by name. Any [A-Za-z]+ role name accepted — we don't bake the
    # current monolith's role enum into the hook (new monoliths use different
    # role names; sql.md is the source of truth on which roles are required).
    grant_count=$(printf '%s' "$content" \
        | grep -ciE "GRANT [A-Z, ]+ ON +(\[[A-Za-z]+\]\.)?\[?$name\]? +TO +\[?[A-Za-z]+\]?" \
        || true)
    if [ "$grant_count" -lt 3 ]; then
        violations="$violations\n  - $bracketed: only $grant_count GRANT statement(s) found (need at least 3 distinct roles per sql.md — e.g. dev/support/release plus module roles)"
    fi

    # IsDeleted column check inside the CREATE TABLE body. Use a small Python
    # script so we can carve out the table body precisely.
    has_is_deleted=$(printf '%s' "$content" | python -c "
import sys, re
src = sys.stdin.read()
name = '$name'
m = re.search(r'CREATE\\s+TABLE\\s+\\[[A-Za-z]+\\]\\.\\[' + re.escape(name) + r'\\]\\s*\\((.*?)\\)\\s*(?:GO|;|\$)', src, re.IGNORECASE | re.DOTALL)
if not m:
    print('1')  # If we can't parse, don't false-positive.
    sys.exit()
body = m.group(1)
print('1' if re.search(r'\\[?IsDeleted\\]?\\s+BIT', body, re.IGNORECASE) else '0')
")
    if [ "$has_is_deleted" = "0" ]; then
        violations="$violations\n  - $bracketed: missing 'IsDeleted BIT NOT NULL DEFAULT 0' (or document why a link/lookup table doesn't need it)"
    fi
done <<< "$tables"

if [ -n "$violations" ]; then
    cat >&2 <<MSG
ENFORCEMENT (SQL migration gate): The migration introduces tables that violate CLAUDE.md sql.md rules:
$(printf '%b' "$violations")

REVISE before re-writing:

1. GRANTs: every new table needs at least 3 distinct GRANT statements. The
   exact roles depend on the monolith — see claude-shared/.claude/rules/sql.md.
   Today's PlatformCode list is FmfxDeveloper, FmfxSupportTeam, FmfxReleaseAPP
   plus module roles (Users, Clients, Shared); other monoliths differ.

2. IsDeleted: include 'IsDeleted BIT NOT NULL DEFAULT 0' on aggregate-backed tables. If this is a true link/lookup table where soft-delete makes no sense, leave a brief SQL comment explaining the omission (e.g. -- link table; row lifetime tied to FK cascade).

See claude-shared/.claude/rules/sql.md and the precedent at 0007-CreateResourceHierarchyView.sql.
MSG
    exit 2
fi

exit 0
