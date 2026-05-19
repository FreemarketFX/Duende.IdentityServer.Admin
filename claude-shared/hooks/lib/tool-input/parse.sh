#!/bin/bash
# Shared helper for PreToolUse / PostToolUse hooks under freemarket-monolith-hooks.
#
# Source this file, then call `tool_input_load` to read stdin once. After that
# `ti_get <field>` returns a top-level field value, and `ti_content` returns
# `content + "\n" + new_string` (covering both Write and Edit shapes).
#
# Both readers prefer `tool_input.<field>` when present (the nested envelope
# Claude Code wraps PreToolUse JSON in) and fall back to the top-level field
# (the synthetic shape used by smoke tests). All extraction is fail-open: if
# Python is missing or JSON parsing breaks, the helpers print empty strings
# and the calling hook will see no match and exit 0.
#
# Usage:
#   . "$(dirname "$0")/../lib/tool-input/parse.sh"
#   tool_input_load
#   file_path=$(ti_get file_path)
#   content=$(ti_content)

tool_input_load() {
    TI_INPUT=$(cat)
}

ti_get() {
    printf '%s' "$TI_INPUT" | python -c "
import sys, json
try:
    d = json.load(sys.stdin)
    ti = d.get('tool_input') if isinstance(d.get('tool_input'), dict) else {}
    print(ti.get('$1','') or d.get('$1',''))
except Exception:
    pass" 2>/dev/null
}

ti_content() {
    printf '%s' "$TI_INPUT" | python -c "
import sys, json
try:
    d = json.load(sys.stdin)
    ti = d.get('tool_input') if isinstance(d.get('tool_input'), dict) else {}
    content = ti.get('content','') or d.get('content','') or ''
    new_string = ti.get('new_string','') or d.get('new_string','') or ''
    print(content + '\n' + new_string)
except Exception:
    pass" 2>/dev/null
}
