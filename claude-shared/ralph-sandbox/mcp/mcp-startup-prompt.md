# Sandbox MCP Startup Gate

Before starting any other work, you must complete this startup sequence. Do not skip or abbreviate it.

## Learnings

Anything you learn whilst running this startup gate should be appended to the section **MCP Learnings for future iterations** at the top of `tasks/current/progress.txt`
Include the tools or commands you found to achieve each task, and patterns that apply broadly.  Avoid adding story-specific details.

You should read this section in `tasks/**/progress.txt` before proceeding.

## Step 1 — Identify Docker-based MCP servers

Read `tasks/config/mcp-servers.yml`. Collect every server entry that has a `docker` field — these are containers the sandbox entrypoint is
starting. Note each server's name (this matches the Docker Compose `container_name`). Also read `.mcp.json` in the project root to get the
full list of configured MCP servers and their URLs.

## Step 2 — Wait for Docker containers to be HEALTHY

Poll every 5 seconds for up to 120 seconds until every container from Step 1 is running and healthy.
Run this as a **single inline Bash command** (do NOT run it in the background):

```bash
TIMEOUT=120; ELAPSED=0; INTERVAL=5
CONTAINERS="<space-separated container names from Step 1>"
while [ $ELAPSED -lt $TIMEOUT ]; do
  ALL_HEALTHY=true
  for NAME in $CONTAINERS; do
    STATUS=$(docker inspect --format='{{.State.Health.Status}}' "$NAME" 2>/dev/null)
    if [ "$STATUS" != "healthy" ]; then
      ALL_HEALTHY=false
      break
    fi
  done
  if [ "$ALL_HEALTHY" = "true" ]; then
    echo "All MCP containers healthy after ${ELAPSED}s"
    break
  fi
  sleep $INTERVAL
  ELAPSED=$((ELAPSED + INTERVAL))
done
if [ "$ALL_HEALTHY" != "true" ]; then
  echo "TIMEOUT: Not all containers healthy after ${TIMEOUT}s"
  docker ps --format 'table {{.Names}}\t{{.Status}}'
  exit 1
fi
```

If the timeout is reached, print the final `docker ps` output and **EXIT. DO NOT PROCEED ANY FURTHER.**

## Step 3 — Verify MCP tools are available in this session

MCP tools are discovered when a Claude Code session starts. If the containers were not yet healthy when this session launched, the tools will
**not** be available — no amount of waiting will fix this. The ralph loop will restart the session once this iteration exits.

**How to verify:** For each MCP server from Step 1, call one of its tools directly:

| Server | Probe call |
|--------|------------|
| `playwright` | Call `playwright_navigate` with url `about:blank` |
| `datadog` | Query `what was the last error log in datadog` |

For any other server not listed above, pick the lightest read-only tool it offers and call it.

**CRITICAL — do NOT use any of these instead:**
- `claude mcp list` or `claude mcp status` via Bash — these check the CLI config, not whether tools are loaded in the current session
- Any other Bash command to check MCP status

**If any tool call fails or the tool is not recognised:**
1. Report which servers are disconnected.
2. Stop immediately. Do not attempt any other work. End your response with:

> FATAL: MCP servers not connected — cannot proceed.
> This is expected for Iteration 1 of a sandbox Ralph loop where the MCP servers are being initialised.

## Step 4 — Proceed

Only after Steps 2 and 3 pass may you begin the assigned task.