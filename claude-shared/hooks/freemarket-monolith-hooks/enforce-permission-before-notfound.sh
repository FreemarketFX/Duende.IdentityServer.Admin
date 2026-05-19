#!/bin/bash
# PreToolUse on Write/Edit for *.Command.cs files. Hard-fail when the new
# content has a NotFound branch ordered BEFORE a HasPermission check, which
# leaks resource existence to anonymous probes (404 vs 403 enumeration).
# Caught in PR #250 (FMFX-15818): CreateInvitation.Command.cs returned
# NotFound for a missing account before evaluating InvitationWrite permission.

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

violation=$(printf '%s' "$content" | python -c '
import sys, re
src = sys.stdin.read()
src = re.sub(r"//[^\n]*", "", src)
src = re.sub(r"/\*.*?\*/", "", src, flags=re.DOTALL)
src = re.sub(r"\"(?:[^\"\\]|\\.)*\"", "\"\"", src)

# Carve out each HandleAsync method body and check ordering inside that body
# only. A *.Command.cs file typically holds the request DTO + validator + handler
# (and sometimes a sibling [LoadPermissions] class), so a top-level NotFound in a
# different class would otherwise false-positive against a HasPermission inside
# the handler.
header = re.compile(r"(?:public|protected|private|internal)\s+(?:override\s+|async\s+|virtual\s+|sealed\s+)*\s*(?:Task<[^>]*>|Task|ValueTask(?:<[^>]*>)?)\s+HandleAsync\s*\([^)]*\)", re.MULTILINE)

violations = []
for m in header.finditer(src):
    i = src.find("{", m.end())
    if i == -1:
        continue
    depth = 1
    j = i + 1
    while j < len(src) and depth > 0:
        c = src[j]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
        j += 1
    body = src[i+1:j-1]
    body_offset = i + 1

    nf = re.search(r"\bnew\s+NotFound\b", body)
    hp = re.search(r"\bHasPermission\s*\(", body)

    if nf and hp and nf.start() < hp.start():
        nf_line = src[:body_offset + nf.start()].count("\n") + 1
        hp_line = src[:body_offset + hp.start()].count("\n") + 1
        violations.append(f"NotFound at line {nf_line}; first HasPermission at line {hp_line}")

print("\n".join(violations))
')

if [ -n "$violation" ]; then
    cat >&2 <<MSG
ENFORCEMENT (permission-before-notfound): $file_path returns NotFound before checking caller permission.

  $violation

This leaks resource existence to anonymous probes: a 404 vs 403 difference lets a caller enumerate IDs without auth. GUIDv7 IDs are timestamp-prefixed, which makes the search space cheap.

Fix: evaluate permission FIRST. Either:
  - Return Forbidden for both missing-resource and missing-permission (caller cannot distinguish), or
  - Return NotFound for both (preferred when the resource type is itself sensitive).

If you genuinely need NotFound first (e.g. a public catalogue endpoint), suppress this hook by adding a NEAREST-line comment on the NotFound assignment:
    // permission-before-notfound: public endpoint, leak is intentional
The hook strips comments before matching, so suppression requires extracting the NotFound branch into a small helper and documenting the call site.

See src/Users/Application/Features/CreateInvitation/CreateInvitation.Command.cs (post-fix) for the canonical ordering.
MSG
    exit 2
fi

exit 0
