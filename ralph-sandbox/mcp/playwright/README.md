# Playwright MCP Server

Browser automation for Claude Code via the [Playwright MCP](https://github.com/anthropics/playwright-mcp) server, running as a Docker Compose service.

## Architecture

```
Claude Code  --HTTP-->  localhost:8931/mcp  ---->  playwright container (headless Chromium)
```

The server runs headless Chromium inside the `mcr.microsoft.com/playwright/mcp` Docker image and exposes an HTTP MCP endpoint on port 8931.

### Files

| File | Purpose |
|---|---|
| `compose.yml` | Base Compose definition — image, ports, healthcheck, network |
| `compose-sandbox.yml` | Sandbox overrides — proxy env vars, CA cert healthcheck gate |
| `compose-sandbox-startup.sh` | Post-start script that injects the sandbox proxy CA cert into the container's NSS trust store |

## Setup

Add an entry to `tasks/config/mcp-servers.yml`:

```yaml
servers:
  playwright:
    type: http
    url: http://localhost:8931/mcp
    docker:
      compose: playwright/compose.yml
      allowedOriginsEnvVar: PLAYWRIGHT_MCP_ALLOWED_ORIGINS  # only required by mcp-startup.ps1 for local execution
      proxyConfigSection: playwright                        # only required by mcp-startup.ps1 for local execution
```

**That's it for sandbox use.** The sandbox entrypoint reads this manifest, pulls the Docker image, starts the container, and generates the `.mcp.json` that Claude Code consumes — all automatically.

## Local development (without Ralph sandbox)

To use Playwright MCP with local Claude Code outside the sandbox, you need Docker Desktop running and PowerShell Core (pwsh).

### Start and stop

```powershell
# Start servers and generate .mcp.json
claude-shared/ralph-sandbox/mcp/mcp-startup.ps1

# Stop servers and remove .mcp.json
claude-shared/ralph-sandbox/mcp/mcp-startup.ps1 -Down
```

### Verify connectivity

Confirm the container is healthy:

```bash
docker ps --format 'table {{.Names}}\t{{.Status}}'
# Should show: playwright   Up ... (healthy)
```

Then verify Claude Code can reach it by asking Claude to list available Playwright tools.

### Domain restrictions

When started via `mcp-startup.ps1`, the server restricts browser navigation to domains listed in `config/proxy-config.yml` under `playwright.allowedDomains`. The startup script converts domain patterns to origins and passes them to the container via the `PLAYWRIGHT_MCP_ALLOWED_ORIGINS` environment variable (semicolon-separated).

| Domain pattern | Origins generated |
|---|---|
| `*.example.com` | `https://*.example.com;http://*.example.com` |
| `*.npmjs.org:443` | `https://*.npmjs.org` |
| `localhost:8080` | `https://localhost:8080;http://localhost:8080` |

Without `proxy-config.yml` (or if the section is missing), the server runs **unrestricted** — backward compatible with manual `docker compose up`.

To verify the restriction reached the container:

```powershell
docker exec playwright env | Select-String "PLAYWRIGHT_MCP_ALLOWED_ORIGINS"
```

## Usage in Claude Code

Once connected, Claude Code gains access to Playwright's browser automation tools. These are the key ones:

| Tool | Description |
|---|---|
| `playwright_navigate` | Navigate to a URL |
| `playwright_screenshot` | Capture a screenshot of the current page |
| `playwright_click` | Click an element (by text, CSS, or coordinates) |
| `playwright_fill` | Type into an input field |
| `playwright_evaluate` | Run arbitrary JavaScript in the page |
| `playwright_get_visible_text` | Extract all visible text from the page |
| `playwright_get_visible_html` | Get the page HTML |

## Example prompts

### Basic navigation and scraping

```
Navigate to https://news.ycombinator.com using Playwright tools,
take a screenshot, and return the top 5 story titles.
```

### Form interaction

```
Using Playwright:
1. Navigate to https://example.com/login
2. Fill in the username field with "testuser" and the password field with "testpass"
3. Click the "Sign In" button
4. Take a screenshot of the resulting page
```

### Visual regression check

```
Using Playwright, navigate to http://localhost:5000/dashboard.
Take a screenshot and describe the layout. Does it match a standard
two-column dashboard with a sidebar on the left?
```

### Extract structured data

```
Using Playwright, navigate to https://example.com/pricing.
Extract all pricing tiers into a markdown table with columns:
Plan Name, Price, and Features.
```

## Sandbox proxy notes

When running inside the Docker sandbox, all outbound traffic from the Playwright container goes through the sandbox's HTTP proxy (`host.docker.internal:3128`). The `compose-sandbox.yml` overrides inject the proxy env vars and the `compose-sandbox-startup.sh` script installs the proxy CA certificate so HTTPS sites load without certificate errors.

If a site fails to load with a TLS error, check that:
1. The domain is listed in the `playwright.allowedDomains` section of `config/proxy-config.yml`
2. The CA cert was injected (container log should show `certutil` output)
3. The container has `NODE_EXTRA_CA_CERTS` set (check with `docker exec playwright env`)

## Adding allowed domains

Domains that Playwright needs to access are managed in the `playwright` section of `config/proxy-config.yml`, separate from the infrastructure domains:

```yaml
playwright:
  allowedDomains:
    - "*.wearefreemarket.com"
    - "*.example.com"        # <-- add new domains here
```

`Sync-ProxyConfig` in `ralph-sandbox.ps1` automatically merges all per-server sections' `allowedDomains` into the network allow-list at runtime, so the generated `proxy-config.json` remains a flat structure with a single `network.allowedDomains` array.
