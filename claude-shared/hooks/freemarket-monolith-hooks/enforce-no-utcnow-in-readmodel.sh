#!/bin/bash
# PreToolUse on Write/Edit for read-side files (*.Query.cs, *ReadModel*Handler.cs).
# Hard-fail when the new content introduces DateTimeOffset.UtcNow or DateTime.UtcNow.
# CLAUDE.md "Aggregate Timestamps" says: NEVER use DateTimeOffset.UtcNow or
# GETUTCDATE() for CreatedOn/LastModifiedOn columns in new code — and for
# computed Status fields, the SQL clock (GETUTCDATE in the SELECT) is the
# source of truth, not the app server clock.
# Caught in PR #250 (FMFX-15818): GetAccountUsers.Query.cs computed Status
# from DateTimeOffset.UtcNow instead of pushing it into the SQL CASE.

set -e

. "$(dirname "$0")/../lib/tool-input/parse.sh"
tool_input_load

file_path=$(ti_get file_path)

# Read-side file patterns. Query handlers and ReadModel handlers must use SQL clock.
case "$file_path" in
    *.Query.cs|*ReadModel*Handler.cs|*ReadModelHandler.cs)
        ;;
    *)
        exit 0
        ;;
esac

content=$(ti_content)

hits=$(printf '%s' "$content" | python -c '
import sys, re
src = sys.stdin.read()
src = re.sub(r"//[^\n]*", "", src)
src = re.sub(r"/\*.*?\*/", "", src, flags=re.DOTALL)
src = re.sub(r"\"(?:[^\"\\]|\\.)*\"", "\"\"", src)
pat = re.compile(r"\b(DateTimeOffset|DateTime)\.UtcNow\b")
print("yes" if pat.search(src) else "")
')

if [ -n "$hits" ]; then
    cat >&2 <<MSG
ENFORCEMENT (no-utcnow-in-readmodel): The new content in $file_path uses \`DateTimeOffset.UtcNow\` or \`DateTime.UtcNow\` in a read-side handler / query.

CLAUDE.md and project convention: SQL is the clock for read-side computations and read-model timestamps. Two reasons:
  - Clock skew between app server and SQL becomes an observable bug for the same row read twice.
  - The same logic ends up duplicated across query handlers and the response builder.

Fix options:
  - Status / expiry / "is past" computations: push into the SELECT as a CASE on GETUTCDATE(),
    e.g. \`CASE WHEN i.ExpiresAt > GETUTCDATE() THEN 'Pending' ELSE 'Expired' END AS Status\`.
  - CreatedOn / LastModifiedOn: use the aggregate's CreatedAt/UpdatedAt (set by the Repository).
    NEVER fall back to DateTimeOffset.UtcNow or GETUTCDATE() in new INSERT/MERGE code.

See src/Users/Application/Features/GetAccountUsers/GetAccountUsers.Query.cs (post-fix) for the canonical pattern.
MSG
    exit 2
fi

exit 0
