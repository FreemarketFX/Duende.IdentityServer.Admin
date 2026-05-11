#!/bin/bash

# Read JSON input from stdin
input=$(cat)

# Parse JSON fields using PowerShell instead of jq
parsed=$(echo "$input" | powershell -NoProfile -Command '
$raw = [Console]::In.ReadToEnd()
$json = $raw.Replace("\","\\") | ConvertFrom-Json
$dir = $json.workspace.current_dir
$model = $json.model.display_name
$ctxPct = [math]::Round($json.context_window.used_percentage)
$inTok = $json.context_window.total_input_tokens
$outTok = $json.context_window.total_output_tokens
$winSize = $json.context_window.context_window_size
Write-Output "$dir|$model|$ctxPct|$inTok|$outTok|$winSize"
')

IFS='|' read -r cwd model ctx_pct in_tokens out_tokens win_size <<< "$parsed"

# Convert cwd for git commands
unix_cwd=$(echo "$cwd" | sed 's|\\|/|g' | sed 's|^\([A-Za-z]\):|/\L\1|')

# Git info
git_info=""
if (cd "$unix_cwd" 2>/dev/null && git rev-parse --git-dir >/dev/null 2>&1); then
    branch=$(cd "$unix_cwd" && git --no-optional-locks rev-parse --abbrev-ref HEAD 2>/dev/null)

    # Dirty file count (staged + unstaged)
    dirty=$(cd "$unix_cwd" && git --no-optional-locks status --porcelain 2>/dev/null | wc -l | tr -d ' ')

    # Ahead/behind remote
    ab=$(cd "$unix_cwd" && git --no-optional-locks rev-list --left-right --count HEAD...@{upstream} 2>/dev/null)
    ahead=$(echo "$ab" | cut -f1 | tr -d ' ')
    behind=$(echo "$ab" | cut -f2 | tr -d ' ')

    ab_info=""
    [ "${ahead:-0}" -gt 0 ] 2>/dev/null && ab_info="↑${ahead}"
    [ "${behind:-0}" -gt 0 ] 2>/dev/null && ab_info="${ab_info}↓${behind}"

    dirty_info=""
    [ "${dirty:-0}" -gt 0 ] 2>/dev/null && dirty_info=" ✏️${dirty}"

    # Stash count
    stash_count=$(cd "$unix_cwd" && git --no-optional-locks stash list 2>/dev/null | wc -l | tr -d ' ')
    stash_info=""
    [ "${stash_count:-0}" -gt 0 ] 2>/dev/null && stash_info=" 📦${stash_count}"

    # Last commit age
    last_commit_ts=$(cd "$unix_cwd" && git --no-optional-locks log -1 --format=%ct 2>/dev/null)
    commit_age=""
    if [ -n "$last_commit_ts" ]; then
        now=$(date +%s)
        diff_sec=$((now - last_commit_ts))
        if [ "$diff_sec" -ge 86400 ]; then
            commit_age=" 🕐$((diff_sec / 86400))d"
        elif [ "$diff_sec" -ge 3600 ]; then
            commit_age=" 🕐$((diff_sec / 3600))h"
        elif [ "$diff_sec" -ge 60 ]; then
            commit_age=" 🕐$((diff_sec / 60))m"
        else
            commit_age=" 🕐${diff_sec}s"
        fi
    fi

    # Rebase/merge/cherry-pick state with severity coloring
    git_dir=$(cd "$unix_cwd" && git rev-parse --git-dir 2>/dev/null)
    git_state=""
    if [ -d "$unix_cwd/$git_dir/rebase-merge" ] || [ -d "$unix_cwd/$git_dir/rebase-apply" ]; then
        git_state=" ⚠️REBASING"
    elif [ -f "$unix_cwd/$git_dir/MERGE_HEAD" ]; then
        git_state=" ⚠️MERGING"
    elif [ -f "$unix_cwd/$git_dir/CHERRY_PICK_HEAD" ]; then
        git_state=" ⚠️CHERRY-PICK"
    fi

    # Merge conflicts with severity coloring
    conflict_count=$(cd "$unix_cwd" && git --no-optional-locks diff --name-only --diff-filter=U 2>/dev/null | wc -l | tr -d ' ')
    conflict_info=""
    if [ "${conflict_count:-0}" -gt 0 ] 2>/dev/null; then
        if [ "$conflict_count" -gt 3 ]; then
            conflict_info=" \033[38;5;196m❌${conflict_count} conflicts\033[0m"
        elif [ "$conflict_count" -gt 1 ]; then
            conflict_info=" \033[38;5;208m❌${conflict_count} conflicts\033[0m"
        else
            conflict_info=" \033[38;5;220m❌${conflict_count} conflict\033[0m"
        fi
    fi

    if [ -n "$branch" ]; then
        git_info=" | 🌿 ${branch}${dirty_info}${stash_info}${commit_age}"
        [ -n "$ab_info" ] && git_info="${git_info} ${ab_info}"
        git_info="${git_info}${git_state}${conflict_info}"
    fi
fi

# ANSI colors
ESC=$'\033'
RST="${ESC}[0m"
GRN="${ESC}[38;5;34m"
YLW="${ESC}[38;5;220m"
ORG="${ESC}[38;5;208m"
RED="${ESC}[38;5;196m"
DIM="${ESC}[38;5;240m"

# Color per bar position (green -> yellow -> orange -> red)
BAR_COLORS=("$GRN" "$GRN" "$GRN" "$YLW" "$YLW" "$YLW" "$ORG" "$ORG" "$RED" "$RED")

# Gradient bar function: gradient_bar <percentage>
gradient_bar() {
    local pct_raw=${1:-0}
    local pct_bar=$pct_raw
    [ "$pct_bar" -gt 100 ] && pct_bar=100
    local bar=""
    local filled=$((pct_bar / 10))
    local empty=$((10 - filled))

    for ((i=0; i<filled; i++)); do
        bar="${bar}${BAR_COLORS[$i]}█"
    done
    for ((i=0; i<empty; i++)); do
        bar="${bar}${DIM}░"
    done

    if [ "$pct_raw" -ge 80 ]; then
        local clr="$RED"
    elif [ "$pct_raw" -ge 60 ]; then
        local clr="$ORG"
    elif [ "$pct_raw" -ge 30 ]; then
        local clr="$YLW"
    else
        local clr="$GRN"
    fi

    echo "${bar} ${clr}${pct_raw}%${RST}"
}

# Context window usage
ctx_info=""
if [ -n "$ctx_pct" ] && [ "$ctx_pct" != "0" ]; then
    ctx_info=" | 📊 ctx $(gradient_bar "$ctx_pct")"
fi

# Total token usage (input+output as % of window size)
usage_info=""
if [ -n "$in_tokens" ] && [ -n "$out_tokens" ] && [ "${win_size:-0}" -gt 0 ] 2>/dev/null; then
    total_tokens=$((in_tokens + out_tokens))
    usage_pct=$((total_tokens * 100 / win_size))
    # Format token count as compact string (e.g. 51k)
    if [ "$total_tokens" -ge 1000000 ]; then
        tok_str="$((total_tokens / 1000000))M"
    elif [ "$total_tokens" -ge 1000 ]; then
        tok_str="$((total_tokens / 1000))k"
    else
        tok_str="$total_tokens"
    fi
    usage_info=" | 🔥 ${tok_str} $(gradient_bar "$usage_pct")"
fi

# Ralph progress indicator
ralph_info=""
# Check for tasks/current/prd.json relative to workspace
ralph_prd=""
for candidate in "$unix_cwd/tasks/current/prd.json" "$unix_cwd/claude-shared/tasks/current/prd.json"; do
    if [ -f "$candidate" ]; then
        ralph_prd="$candidate"
        break
    fi
done
# Also check for multi-app layout (apps/*/tasks/current/prd.json)
if [ -z "$ralph_prd" ]; then
    for candidate in "$unix_cwd"/apps/*/tasks/current/prd.json; do
        if [ -f "$candidate" ]; then
            ralph_prd="$candidate"
            break
        fi
    done
fi

if [ -n "$ralph_prd" ]; then
    # Count total stories and completed stories using PowerShell
    ralph_parsed=$(powershell -NoProfile -Command "
        \$j = Get-Content '$ralph_prd' -Raw | ConvertFrom-Json
        \$total = \$j.userStories.Count
        \$done = (\$j.userStories | Where-Object { \$_.passes -eq \$true }).Count
        Write-Output \"\$done|\$total\"
    " 2>/dev/null)
    if [ -n "$ralph_parsed" ]; then
        IFS='|' read -r ralph_done ralph_total <<< "$ralph_parsed"
        if [ "${ralph_total:-0}" -gt 0 ] 2>/dev/null; then
            if [ "$ralph_done" -eq "$ralph_total" ]; then
                ralph_info=" | 🤖 Ralph ✅ ${ralph_done}/${ralph_total}"
            else
                ralph_info=" | 🤖 Ralph ${ralph_done}/${ralph_total}"
            fi
        fi
    fi
fi

# Output (echo -e to interpret ANSI codes)
echo -e "📁 ${cwd}${git_info} | 🤖 ${model}${ctx_info}${usage_info}${ralph_info}"
