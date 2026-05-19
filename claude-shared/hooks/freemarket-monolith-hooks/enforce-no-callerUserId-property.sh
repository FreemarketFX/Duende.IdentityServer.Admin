#!/bin/bash
# PreToolUse on Write/Edit for *.Command.cs files. Hard-fail when the new
# content declares a `CallerUserId` property — it duplicates `AuthorizationId`
# from `InternalCommand<T>` (PlatformCode base). A second name forces every
# reader to verify they're identical, and tests can drift them apart.
# Caught in PR #250 (FMFX-15818): CreateInvitationCommand had both.

set -e

. "$(dirname "$0")/../lib/tool-input/parse.sh"
tool_input_load

file_path=$(ti_get file_path)

case "$file_path" in
    *.Command.cs)
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
# Match property declarations like:
#   public string CallerUserId { get; ... }
#   public Guid CallerUserId { get; init; }
#   public required string CallerUserId { get; set; }
# Also match constructor parameter form for primary ctors:
#   string callerUserId
# (case-insensitive on the leading char to catch ctor params).
prop = re.search(r"\b(public|internal|protected|private)\s+[\w<>?]+\s+CallerUserId\b", src)
ctor = re.search(r"\b[Cc]allerUserId\b\s*[,)=]", src)
if prop:
    print("property: " + prop.group(0))
elif ctor:
    print("ctor parameter or assignment: CallerUserId")
')

if [ -n "$hits" ]; then
    cat >&2 <<MSG
ENFORCEMENT (no-callerUserId-property): The new content in $file_path introduces a \`CallerUserId\` member:

  $hits

\`InternalCommand<T>\` (PlatformCode base) already exposes \`AuthorizationId\` carrying the same value. A second name forces every reader to verify the two are identical, and tests can drift them apart.

Fix:
  - Delete the \`CallerUserId\` property and any constructor parameter that feeds it.
  - In the handler, replace \`command.CallerUserId\` with \`command.AuthorizationId!\`.
  - Update the endpoint to stop passing the value separately — \`InternalCommand\` resolves it from the auth context.

See src/Users/Application/Features/CreateInvitation/CreateInvitation.Command.cs (post-fix).
MSG
    exit 2
fi

exit 0
