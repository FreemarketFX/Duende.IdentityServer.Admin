#!/bin/bash

# Session Summary Script
# Prints a summary of git activity in the current session.
# Usage: bash session-summary.sh [minutes_ago]
#   minutes_ago: how far back to look (default: 480 = 8 hours)

MINUTES_AGO=${1:-480}
SINCE=$(date -d "-${MINUTES_AGO} minutes" '+%Y-%m-%d %H:%M' 2>/dev/null || date -v-${MINUTES_AGO}M '+%Y-%m-%d %H:%M' 2>/dev/null)

ESC=$'\033'
RST="${ESC}[0m"
BOLD="${ESC}[1m"
GRN="${ESC}[38;5;34m"
YLW="${ESC}[38;5;220m"
CYN="${ESC}[38;5;45m"
DIM="${ESC}[38;5;240m"

echo -e "${BOLD}📋 Session Summary${RST} ${DIM}(last ${MINUTES_AGO}m)${RST}"
echo -e "${DIM}$(printf '─%.0s' {1..50})${RST}"

# Commits made
commit_count=$(git --no-optional-locks log --oneline --since="${MINUTES_AGO} minutes ago" 2>/dev/null | wc -l | tr -d ' ')
if [ "${commit_count:-0}" -gt 0 ]; then
    echo -e "\n${GRN}📝 Commits: ${commit_count}${RST}"
    git --no-optional-locks log --oneline --since="${MINUTES_AGO} minutes ago" 2>/dev/null | while read -r line; do
        echo -e "   ${DIM}•${RST} $line"
    done
else
    echo -e "\n${DIM}📝 No commits in this session${RST}"
fi

# Files changed (staged + unstaged)
changed_files=$(git --no-optional-locks diff --name-only 2>/dev/null | wc -l | tr -d ' ')
staged_files=$(git --no-optional-locks diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ')
untracked_files=$(git --no-optional-locks ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')

echo -e "\n${CYN}📂 Working Tree${RST}"
echo -e "   Modified:  ${changed_files:-0}"
echo -e "   Staged:    ${staged_files:-0}"
echo -e "   Untracked: ${untracked_files:-0}"

# Diff stats for uncommitted changes
diff_stat=$(git --no-optional-locks diff --stat HEAD 2>/dev/null | tail -1)
if [ -n "$diff_stat" ]; then
    echo -e "   ${DIM}${diff_stat}${RST}"
fi

# Branch info
branch=$(git --no-optional-locks rev-parse --abbrev-ref HEAD 2>/dev/null)
if [ -n "$branch" ]; then
    ab=$(git --no-optional-locks rev-list --left-right --count HEAD...@{upstream} 2>/dev/null)
    ahead=$(echo "$ab" | cut -f1 | tr -d ' ')
    behind=$(echo "$ab" | cut -f2 | tr -d ' ')
    branch_info="🌿 ${branch}"
    [ "${ahead:-0}" -gt 0 ] 2>/dev/null && branch_info="${branch_info} ↑${ahead} unpushed"
    [ "${behind:-0}" -gt 0 ] 2>/dev/null && branch_info="${branch_info} ↓${behind} behind"
    echo -e "\n${YLW}${branch_info}${RST}"
fi

# Stashes
stash_count=$(git --no-optional-locks stash list 2>/dev/null | wc -l | tr -d ' ')
if [ "${stash_count:-0}" -gt 0 ] 2>/dev/null; then
    echo -e "\n${DIM}📦 ${stash_count} stash(es)${RST}"
fi

echo -e "\n${DIM}$(printf '─%.0s' {1..50})${RST}"
