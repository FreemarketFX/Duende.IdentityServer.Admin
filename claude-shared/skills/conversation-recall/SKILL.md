---
name: conversation-recall
description: "Inspect prior session transcripts to find earlier decisions, prompts, or solutions. Helpful when looking up something discussed before. Triggered phrases: recall conversation, find past discussion, search history, remember session."
license: MIT
---

# Conversation Recall

Search, summarize, and learn from past Claude Code conversations stored on disk.

Two modes: **quick** (cache + history index, no agents) and **deep** (full session reads, agent summarization). Quick is the default. Escalate to deep only when quick doesn't answer the question.

---

## Step 0: Check Memory

Scan MEMORY.md (already in context) and linked files. If an entry answers the query, deliver immediately and offer to go deeper. Zero tool calls.

---

## Step 1: Parse Intent + Keywords

Classify `$ARGUMENTS`:

| Intent | Default? | Action |
|--------|----------|--------|
| **answer** | **Yes** | Direct answer from history |
| **search** | No — only for "what have I been working on" | List sessions |
| **summarize** | No — explicit request | Full session overview |
| **learn** | No — explicit request | Extract + save to memory |

Extract **keywords** (technical terms, nouns, verbs), **date hints**, **project hints**, **session ID**.

### Date resolution

When the query contains a date reference ("yesterday", "last week", "March 15"), resolve it to a millisecond timestamp range **before** searching. **Never calculate timestamps by hand or hardcode epoch values.**

Use GNU `date` (available in Git Bash):
```bash
# Single day — e.g. "yesterday"
START=$(($(date -d "yesterday 00:00:00" +%s) * 1000))
END=$(($(date -d "today 00:00:00" +%s) * 1000))
echo "start=$START end=$END"

# Date range — e.g. "last week", "first week of March"
START=$(($(date -d "2026-03-01 00:00:00" +%s) * 1000))
END=$(($(date -d "2026-03-08 00:00:00" +%s) * 1000))
echo "start=$START end=$END"
```

Then filter history.jsonl using the resolved timestamps. Use `awk` for fast numeric comparison — never regex-match on timestamp digits:
```bash
awk -F'"timestamp":' -v start=$START -v end=$END '
  NF>1 { split($2,a,","); ts=int(a[1]);
    if (ts>=start && ts<end) print }
' ~/.claude/history.jsonl
```

Pipe the output through standard tools to group by session and summarize:
```bash
awk -F'"timestamp":' -v start=$START -v end=$END '
  NF>1 { split($2,a,","); ts=int(a[1]);
    if (ts>=start && ts<end) print }
' ~/.claude/history.jsonl | \
  grep -oP '"sessionId":"[^"]+"' | sort | uniq -c | sort -rn
```

---

## Quick Search (default)

Fastest path. Goal: answer in 1-3 tool calls.

### 1. Grep history index

`~/.claude/history.jsonl` — one line per user prompt:
```
{"display":"prompt text","timestamp":1770652292985,"project":"C:\\dev\\ClientActions","sessionId":"db490e7b-..."}
```

Grep with regex alternation: `keyword1|keyword2|related_term`. Never read the whole file.

**Noise filter** — skip: starts with `!` or `/`, shorter than 10 chars, filler words (yes/no/ok/exit/continue/push/commit).

### 2. Rank candidates

Group by `sessionId`:
```
score = 0
for each unique keyword matched: score += 2
if 2+ different keywords in same session: score += 3
today/yesterday: score += 2 | this week: score += 1
20+ prompts: score += 2 | 10-20 prompts: score += 1
```
Minimum score: **3**. Keep top 5.

### 3. Check cache

Glob for `~/.claude/projects/{PROJECT_ENCODED}/{SESSION_ID}.summary.md`

- **Cache hit**: read summary, deliver immediately. No staleness check in quick mode.
- **Cache miss + answer intent**: show the matching prompts from history.jsonl with session IDs. Ask if user wants a deep read.
- **Cache miss + search intent**: show session list with first prompt and `claude --resume SESSION_ID`.

**Quick search is done.** If the cache answered the question, stop here. If not, escalate to deep.

---

## Deep Search (on demand)

Triggered when: quick search didn't answer, user asks to go deeper, learn intent, summarize intent, or no results from quick.

### 1. Staleness check (if cache exists)

Batch all checks in one call: `Bash: wc -l file1.jsonl file2.jsonl ...`

Invalidate if `abs(actual_lines - cached_lines) > 50` or `lines` field missing.

### 2. Deep search fallback (if quick found < 2 results)

Grep session JSONL files directly — catches things Claude said that the user didn't type:
```
Grep: ~/.claude/projects/{PROJECT_ENCODED}/*.jsonl
```
`head_limit: 20`. Deduplicate by sessionId. One attempt only.

### 3. Extract conversation from session JSONL

**Always use `jq` to extract conversation text** — never have an LLM parse JSONL. This runs in <1s on any session file:

```bash
jq -r '
  if .type == "user" and (.isMeta // false | not) then
    (
      if (.message.content | type) == "string" then .message.content
      elif (.message.content | type) == "array" then
        [.message.content[] | select(.type == "text") | .text] | join(" ")
      else ""
      end
    ) | gsub("\n"; " ") | if length > 0 then "USER: " + .[:300] else empty end
  elif .type == "assistant" then
    (
      [.message.content[]? | select(.type == "text") | .text] | join(" ")
      | gsub("\n"; " ")
      | if length > 0 then "ASSISTANT: " + .[:300] else empty end
    )
  else empty
  end
' ~/.claude/projects/{PROJECT_ENCODED}/{SESSION_ID}.jsonl
```

### 4. Summarize extracted conversation

**Single session** (answer/search intent): pipe `jq` output to a temp file, Read it inline, summarize in main context. No agent needed.

**Multiple sessions** (summarize/learn intent, or caching): write `jq` output to a temp file per session, then launch one Haiku agent per session in a **single message**. Agent reads the **extracted text file** (not the raw JSONL):

```
Agent prompt (model: haiku):
Read the file at {TEMP_FILE_PATH}. This is a conversation extract (USER/ASSISTANT pairs).

Return EXACTLY:
---
session_id: {SESSION_ID}
date: [YYYY-MM-DD — derive from context or use "unknown"]
lines: {LINE_COUNT from wc -l of original JSONL}
---
**Summary:** [2-3 sentences]
**Key decisions:** [bullet list]
**Outcome:** [files changed, PRs, conclusions reached]
**Open items:** [unfinished work, or "None"]
```

Clean up temp files after agents complete.

### 5. Cache new summaries

Write as sidecar `.summary.md`. The `lines` field enables staleness detection.

---

## Output Formats

### Answer
Direct answer citing exchanges. Example: "In session abc123, you decided to use parallel flags because..."

### Search
Every session gets its own entry with its own resume link. Never group multiple sessions under one resume link.
```
1. **[Date] - [Project]** — [Summary or first prompt]
   Resume: `claude --resume SESSION_ID`

2. **[Date] - [Project]** — [Summary or first prompt]
   Resume: `claude --resume SESSION_ID`
```

### Summarize
```
## Session Summary
**Date:** [date] | **Project:** [project]
### What happened — ### Decisions — ### Outcomes — ### Open items
```

### Learn
Extract learnings, save to memory by default, show what was saved. Record source session ID for provenance.

---

## Memory Update (Learn Intent)

1. Read `~/.claude/projects/{PROJECT_ENCODED}/memory/MEMORY.md`
2. Organize under existing headings or create new ones
3. Rules: no duplicates, 1-2 lines each, MEMORY.md under 200 lines, detailed notes in linked files

---

## Reference

**Path encoding:** Replace `:` and `\` with `-` (Windows: `C:\dev\X` → `C--dev-X`). Unix: `/` → `-`.

**Cross-project:** Default to current project. Broaden only if user mentions another or nothing found. `Glob: "*" in "~/.claude/projects/"`

**Error handling:**
- history.jsonl missing → tell user, may be fresh install
- Session corrupted/locked → skip, note which
- Bad cache frontmatter → treat as uncached
- Agent garbage → discard, note in output
- 0 results after broadening → tell user, suggest different keywords

**Rules:**
- Use Glob/Grep/Read, not bash equivalents (except where Bash is specified below)
- Bash for: `date` (timestamp resolution), `awk` (timestamp filtering), `jq` (JSONL extraction), `wc -l` (staleness checks)
- Never have an LLM parse raw JSONL — always extract with `jq` first
- Single session → read extracted text inline, no agent
- Multiple sessions → jq + Haiku agents in a single message
- Always provide `claude --resume SESSION_ID`
- Check cache before extraction. Clean up temp files.
