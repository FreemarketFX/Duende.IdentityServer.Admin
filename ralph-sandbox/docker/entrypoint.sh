#!/bin/bash
set -e

# Entrypoint for Ralph sandbox container.
# Symlinks Claude credentials and skills from the host mount, then execs the agent.
# Missing credentials or skills are fatal — the sandbox cannot function without them.

CREDENTIAL_FILE=".credentials.json"
DESTINATION_PATH="/home/agent/.claude"
LOG="/var/log/entrypoint.log"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a $LOG; }

log "Entrypoint starting"

# --- Credentials ---
CREDENTIAL=$(find /c/Users/*/.claude -maxdepth 1 -name "$CREDENTIAL_FILE" -type f 2>/dev/null | head -n 1)

if [ -z "$CREDENTIAL" ]; then
    log "FATAL: $CREDENTIAL_FILE not found under /c/Users/*/.claude — sandbox cannot authenticate"
    exit 1
fi

ln -sf "$CREDENTIAL" "$DESTINATION_PATH/$CREDENTIAL_FILE"
log "Credentials: $CREDENTIAL --> $DESTINATION_PATH/$CREDENTIAL_FILE"

# --- KSM secrets ---
KEEPER_FILE=$(find /c/Users/*/.claude -maxdepth 1 -name ".keeper" -type f 2>/dev/null | head -n 1)

if [ -z "$KEEPER_FILE" ]; then
    log "FATAL: .keeper not found under /c/Users/*/.claude — sandbox cannot fetch secrets"
    exit 1
fi

ksm profile import -p ClaudeDockerSandbox "$(cat "$KEEPER_FILE")"
log "KSM profile imported from $KEEPER_FILE"
ksm profile list 2>&1 | tee -a $LOG

# --- Interpolate persistent env vars ---
ksm interpolate /home/agent/sandbox-persistent.template --output-file /home/agent/sandbox-persistent.sh
cp /home/agent/sandbox-persistent.sh /etc/sandbox-persistent.sh
rm -f /home/agent/sandbox-persistent.template /home/agent/sandbox-persistent.sh
log "KSM interpolation complete for /etc/sandbox-persistent.sh"

# --- Skills ---
SKILLS_PATH=""
if compgen -G "/c/Users/*/.claude/plugins/cache/freemarket-tools/freemarket-claude-skills/*/skills" > /dev/null 2>&1; then
    SKILLS_PATH=$(ls -d /c/Users/*/.claude/plugins/cache/freemarket-tools/freemarket-claude-skills/*/skills 2>/dev/null | sort -V | tail -1)
fi

if [ -z "$SKILLS_PATH" ]; then
    log "FATAL: No freemarket-claude-skills found in plugin cache — /post-ralph will not be available"
    exit 1
fi

ln -sf "$SKILLS_PATH" "$DESTINATION_PATH/skills"
log "Skills: $SKILLS_PATH --> $DESTINATION_PATH/skills"

# --- MCP container startup (only when manifest exists) ---
# Convert Windows path to Linux mount path: C:\claude\mcp -> /c/claude/mcp
DRIVE_LETTER=$(echo "$WORKSPACE_DIR" | cut -c1 | tr '[:upper:]' '[:lower:]')
REPO_PATH="/$DRIVE_LETTER$(echo "$WORKSPACE_DIR" | cut -c3- | sed 's|\\|/|g')"

# --- Worktree .git fixup ---
# When running from a git worktree, the .git file contains a Windows-style
# gitdir pointer that Linux git cannot resolve. Rewrite to Linux mount path.
GIT_FILE="$REPO_PATH/.git"
if [ -f "$GIT_FILE" ]; then
    GIT_LINE1=$(head -1 "$GIT_FILE")
    if echo "$GIT_LINE1" | grep -q '^gitdir:'; then
        ORIGINAL_GITDIR=$(echo "$GIT_LINE1" | sed 's/^gitdir: //')
        if echo "$ORIGINAL_GITDIR" | grep -qE '^[A-Za-z]:/'; then
            [ ! -f "${GIT_FILE}.windows-original" ] && cp "$GIT_FILE" "${GIT_FILE}.windows-original"
            LINUX_GITDIR=$(echo "$ORIGINAL_GITDIR" | sed 's|^\([A-Za-z]\):|/\L\1|')
            echo "gitdir: $LINUX_GITDIR" > "$GIT_FILE"
            log "Worktree .git fixup: $ORIGINAL_GITDIR -> $LINUX_GITDIR"
        fi
    fi
fi

MCP_MANIFEST="$REPO_PATH/tasks/config/mcp-servers.yml"
MCP_COMPOSE_DIR="$REPO_PATH/claude-shared/ralph-sandbox/mcp"
MCP_JSON="$REPO_PATH/.mcp.json"

# --- Resolve env var references in .mcp.json ---
if [ -f "$MCP_JSON" ] && grep -q '${' "$MCP_JSON"; then
  source /etc/sandbox-persistent.sh
  envsubst < "$MCP_JSON" > /tmp/.mcp.json
  cp /tmp/.mcp.json "$MCP_JSON"
  rm -f /home/agent/.claude/mcp-needs-auth-cache.json
  log "Resolved env var references in .mcp.json"
fi

if [ -f "$MCP_MANIFEST" ]; then
  log "Reading MCP manifest: $MCP_MANIFEST"

  # Wait for Docker daemon (needed for compose and image loading)
  log "Wait for Docker daemon to be ready"
  retries=30
  while [ $retries -gt 0 ] && ! docker info >/dev/null 2>&1; do
    sleep 1
    retries=$((retries - 1))
  done

  if ! docker info >/dev/null 2>&1; then
    log "ERROR: Docker daemon not available after 30s — skipping MCP startup"
  else
    log "Docker daemon ready"

    # Pre-stage cached Docker images from host
    for TAR in "$REPO_PATH"/tasks/images/*.tar; do
      [ -f "$TAR" ] || continue
      log "Loading cached image: $TAR"
      docker load -i "$TAR" >> $LOG 2>&1 || \
        log "WARNING: Failed to load image: $TAR"
    done

    # Get server names that have a docker.compose reference
    SERVERS=$(yq '.servers | to_entries[] | select(.value.docker.compose) | .key' "$MCP_MANIFEST" 2>/dev/null)

    for SERVER in $SERVERS; do
      COMPOSE_FILE=$(yq ".servers.$SERVER.docker.compose" "$MCP_MANIFEST")
      COMPOSE_PATH="$MCP_COMPOSE_DIR/$COMPOSE_FILE"

      if [ ! -f "$COMPOSE_PATH" ]; then
        log "WARNING: Compose file not found: $COMPOSE_PATH"
        continue
      fi

      # Build env var arguments from sandbox_env
      ENV_ARGS=""
      SANDBOX_KEYS=$(yq ".servers.$SERVER.docker.sandbox_env // {} | keys | .[]" "$MCP_MANIFEST" 2>/dev/null)
      for KEY in $SANDBOX_KEYS; do
        VALUE=$(yq ".servers.$SERVER.docker.sandbox_env.$KEY" "$MCP_MANIFEST")
        ENV_ARGS="$ENV_ARGS $KEY=$VALUE"
      done

      # Build compose file arguments (layer sandbox overrides if present)
      SANDBOX_COMPOSE="${COMPOSE_PATH%.yml}-sandbox.yml"
      COMPOSE_ARGS="-f $COMPOSE_PATH"
      if [ -f "$SANDBOX_COMPOSE" ]; then
        COMPOSE_ARGS="$COMPOSE_ARGS -f $SANDBOX_COMPOSE"
        log "Layering sandbox overrides: $(basename $SANDBOX_COMPOSE)"
      fi

      log "Starting MCP container: $SERVER (compose: $COMPOSE_FILE${ENV_ARGS:+, env:$ENV_ARGS})"
      env $ENV_ARGS docker compose $COMPOSE_ARGS up -d >> $LOG 2>&1 || \
        log "WARNING: Failed to start $SERVER"

      SERVER_HEALTHY=true

      # Run sandbox startup script if present
      SANDBOX_STARTUP="${COMPOSE_PATH%.yml}-sandbox-startup.sh"
      if [ -f "$SANDBOX_STARTUP" ]; then
        log "Running sandbox startup script: $(basename $SANDBOX_STARTUP)"
        if ! bash "$SANDBOX_STARTUP" >> $LOG 2>&1; then
          log "WARNING: Sandbox startup script failed for $SERVER"
          SERVER_HEALTHY=false
        fi
      fi

      # Wait for exposed ports to be reachable
      PORTS=$(yq '.services[].ports[]' "$COMPOSE_PATH" 2>/dev/null | tr -d '"' | cut -d: -f1)
      for PORT in $PORTS; do
        log "Waiting for port $PORT ($SERVER)..."
        retries=30
        while [ $retries -gt 0 ] && ! bash -c "echo > /dev/tcp/localhost/$PORT" 2>/dev/null; do
          sleep 1
          retries=$((retries - 1))
        done
        if bash -c "echo > /dev/tcp/localhost/$PORT" 2>/dev/null; then
          log "Port $PORT ready for $SERVER"
        else
          log "WARNING: Port $PORT not available after 30s for $SERVER"
          SERVER_HEALTHY=false
        fi
      done

      # Write marker inside each running container via docker exec
      if [ "$SERVER_HEALTHY" = true ]; then
        CONTAINERS=$(yq -r '.services | keys | .[]' "$COMPOSE_PATH" 2>/dev/null)
        for CONTAINER in $CONTAINERS; do
          env $ENV_ARGS docker compose $COMPOSE_ARGS exec -T "$CONTAINER" touch /tmp/healthy 2>/dev/null && \
            log "Marker written inside container: $CONTAINER" || \
            log "WARNING: Could not write marker inside container: $CONTAINER"
        done
      fi
    done
  fi
else
  log "No MCP manifest found at $MCP_MANIFEST — skipping"
fi

# Execute the main command
log "Starting main"
exec "$@"
