# Datadog MCP Server

Observability and monitoring for Claude Code via the [Datadog MCP](https://docs.datadoghq.com/mcp/) server, connecting to Datadog's hosted HTTP endpoint.

## Architecture

```
Claude Code  --HTTP-->  https://mcp.datadoghq.eu/api/unstable/mcp-server/mcp  (Datadog-hosted)
```

Datadog is a remote HTTP server — no Docker container is needed. Authentication is via API keys passed as HTTP headers, resolved from Keeper Secrets Manager (KSM).

## Setup

### 1. Add to mcp-servers.yml

Add an entry to `tasks/config/mcp-servers.yml`:

```yaml
servers:
  datadog:
    type: http
    url: "https://mcp.datadoghq.eu/api/unstable/mcp-server/mcp"
    headers:
      DD_API_KEY: "${DD_API_KEY}"
      DD_APPLICATION_KEY: "${DD_APPLICATION_KEY}"
```

The `${...}` references are resolved automatically from KSM secrets defined in `config/sandbox-persistent.template`.

### 2. Ensure proxy allows Datadog domains

The following domains must be in `config/proxy-config.yml` under `network.allowedDomains`:

```yaml
# Datadog
- "*.datadoghq.eu:443"
- "*.datadoghq.com:443"
```

These are already included in the default proxy config.

## Secret resolution

The API keys are stored in Keeper Secrets Manager and referenced in `config/sandbox-persistent.template`:

```
export DD_API_KEY=keeper://<record-id>/field/PAT
export DD_APPLICATION_KEY=keeper://<record-id>/field/PAT
```

### In the sandbox

The sandbox entrypoint runs `ksm interpolate` to resolve these into `/etc/sandbox-persistent.sh`. Before each `docker sandbox run`, `ralph-sandbox.ps1` uses `envsubst` inside the sandbox to substitute the resolved values into `.mcp.json`.

### Locally

`mcp-startup.ps1` handles this automatically:

1. Detects `${...}` references in the generated `.mcp.json`
2. Fetches the KSM profile from Azure Key Vault
3. Runs `ksm interpolate` on the template to resolve secrets
4. Substitutes resolved values into `.mcp.json`
5. Cleans up the KSM profile

**Prerequisites for local use:**
- [KSM CLI](https://docs.keeper.io/en/secrets-manager/secrets-manager/secrets-manager-command-line-interface/init-command) installed and on PATH
- Azure CLI (`az`) logged into the correct tenant

## Local development (without Ralph sandbox)

### Start

```powershell
claude-shared/ralph-sandbox/mcp/mcp-startup.ps1
```

This generates `.mcp.json` with resolved secrets. No Docker containers are started for Datadog since it's a remote server.

### Stop

```powershell
claude-shared/ralph-sandbox/mcp/mcp-startup.ps1 -Down
```

### Verify connectivity

After starting Claude Code, ask it to query Datadog — e.g. "what was the last error log in datadog". If the keys were resolved correctly, the MCP server will respond.
