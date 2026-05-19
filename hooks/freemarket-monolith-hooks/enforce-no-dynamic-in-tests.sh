#!/bin/bash
# PreToolUse on Write/Edit for test/**/*.cs files. Hard-fail when the new
# content introduces the `dynamic` keyword. Typed records are always available
# for query result rows; `dynamic` defeats the type system, hides column-rename
# bugs, and makes refactors silently miscompile.

set -e

. "$(dirname "$0")/../lib/tool-input/parse.sh"
tool_input_load

file_path=$(ti_get file_path)

# Only enforce inside the test tree, on .cs files.
case "$file_path" in
    */test/*.cs|*\\test\\*.cs)
        ;;
    *)
        exit 0
        ;;
esac

content=$(ti_content)

# Strip comments and string literals so we do not false-positive on prose.
hits=$(printf '%s' "$content" | python -c '
import sys, re
src = sys.stdin.read()
src = re.sub(r"//[^\n]*", "", src)
src = re.sub(r"/\*.*?\*/", "", src, flags=re.DOTALL)
src = re.sub(r"\"(?:[^\"\\]|\\.)*\"", "\"\"", src)
print("yes" if re.search(r"\bdynamic\b", src) else "")
')

if [ -n "$hits" ]; then
    cat >&2 <<MSG
ENFORCEMENT (no-dynamic-in-tests): The new content introduces the \`dynamic\` keyword in $file_path.

\`dynamic\` defeats the type system, hides column-rename bugs in projection rows, and makes refactors silently miscompile. There is no test carve-out for it.

For SQL projection rows in tests, declare a typed record matching the columns:

    private sealed record FooProjectionRow(Guid Id, string Email, DateTimeOffset CreatedAt);
    var rows = await db.Query<FooProjectionRow>(sql, new { ... });

For dictionary-shaped data, prefer \`IDictionary<string, object?>\` or a typed record over \`dynamic\`.
MSG
    exit 2
fi

exit 0
