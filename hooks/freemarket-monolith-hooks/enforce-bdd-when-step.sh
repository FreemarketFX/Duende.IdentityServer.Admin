#!/bin/bash
# PreToolUse on Write/Edit for *.Specs.cs files. Hard-fail when a [Fact] or
# [Theory] test method contains a Then(...) call without a preceding When(...)
# in the same method. CLAUDE.md (testing.md) requires strict Given/When/Then
# ordering — When is mandatory, not implicit-inside-Then.

set -e

. "$(dirname "$0")/../lib/tool-input/parse.sh"
tool_input_load

file_path=$(ti_get file_path)

case "$file_path" in
    *.Specs.cs)
        ;;
    *)
        exit 0
        ;;
esac

content=$(ti_content)

# Carve out each test method and check each one for Then-without-When.
violations=$(printf '%s' "$content" | python -c '
import sys, re

src = sys.stdin.read()
# Find each [Fact]/[Theory] attribute followed by a method body. We grab the
# method name + body using a brace-balanced scan starting after the method
# signature.

attr_pattern = re.compile(r"\[(Fact|Theory)[^\]]*\]\s*(?:public\s+)?(?:async\s+)?(?:Task|ValueTask|void)\s+(\w+)\s*\([^)]*\)", re.MULTILINE)

violations = []
for m in attr_pattern.finditer(src):
    method_name = m.group(2)
    # Find the opening brace after the method signature.
    i = src.find("{", m.end())
    if i == -1:
        continue
    depth = 1
    j = i + 1
    while j < len(src) and depth > 0:
        if src[j] == "{":
            depth += 1
        elif src[j] == "}":
            depth -= 1
        j += 1
    body = src[i+1:j-1]

    # Strip out comments and string literals to avoid false positives.
    body_clean = re.sub(r"//[^\n]*", "", body)
    body_clean = re.sub(r"/\*.*?\*/", "", body_clean, flags=re.DOTALL)
    body_clean = re.sub(r"\"(?:[^\"\\]|\\.)*\"", "\"\"", body_clean)

    has_then = bool(re.search(r"\bThen(?:Async)?\s*\(", body_clean))
    has_when = bool(re.search(r"\bWhen(?:Async)?\s*\(", body_clean))

    if has_then and not has_when:
        violations.append(method_name)

print("\n".join(violations))
')

if [ -n "$violations" ]; then
    cat >&2 <<MSG
ENFORCEMENT (BDD When-step gate): These test methods call Then(...) without a preceding When(...) in the same method body:

$(printf '%s' "$violations" | sed 's/^/  - /')

CLAUDE.md (testing.md) requires strict Given/When/Then ordering. The When step is mandatory — it must be its own step, not implicit inside the Then assertion (e.g. don't write Then(SomethingThrows); restructure as When(DoingSomething); Then(ItThrew)).

For throws-tests:
  - When step captures the action (often by invoking a method that throws and stashing the exception)
  - Then step asserts on the captured outcome

See test/Users.Tests/Unit/Behaviour/CreateUserCommandHandler.Specs.cs for the canonical pattern.
MSG
    exit 2
fi

exit 0
