# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Claude Container is a Podman container for running Claude Code with `--dangerously-skip-permissions` in an isolated environment. It provides network firewall restrictions, MSSQL database tools (ODBC Driver 18, pyodbc, go-sqlcmd), and pre-configured MCP servers.

## Build and Run Commands

```bash
# Build the container image
./claude-run.sh --build

# Build without cache
./claude-run.sh --build-no-cache

# Run Claude in current directory
./claude-run.sh

# Run in specific project directory
./claude-run.sh /path/to/project

# Resume last session
./claude-run.sh -- --resume

# Get shell access to container
./claude-run.sh --shell

# Show status
./claude-run.sh --status
```

## Testing

```bash
# Run database integration tests (requires MSSQL server)
./tests/integration/test-db-integration.sh

# Test from container
podman run --rm \
    -v $(pwd)/tests:/workspace/tests:ro \
    -v $(pwd)/.env.test:/workspace/.env.test:ro \
    --entrypoint "" \
    claude-container:latest \
    /workspace/tests/integration/test-db-integration.sh
```

## Architecture

### Entry Flow
1. `claude-run.sh` - Host-side wrapper that handles image management, authentication, and container launching
2. `scripts/entrypoint.sh` - Container startup: initializes firewall, verifies auth, runs project hooks, launches Claude
3. `scripts/init-firewall.sh` - Configures iptables whitelist (allows Anthropic API, npm, GitHub, pypi, MSSQL host)

### Container Naming
Each container gets a unique name: `claude_<project>_<HH-MM-SS>` (e.g., `claude_my-project_14-32-05`). This allows running multiple instances simultaneously on different projects.

### Key Components
- **Containerfile** - Alpine-based multi-stage build (~352MB). Installs ODBC Driver 18, Claude Code via npm, creates non-root `claude` user
- **scripts/claude-web** - Runtime firewall toggle for web access (`claude-web on/off`)
- **scripts/claude-status** - Diagnostics display (versions, firewall state, MCP servers)
- **scripts/session-save.sh** - SessionEnd hook that copies transcripts to `.claude-sessions/` and commits to git

### MCP Servers (config/mcp.json)
- **Filesystem** - File operations restricted to `/workspace`
- **MSSQL** - Database queries via `mssql_mcp_server`
- **Memory** - Cross-session knowledge graph
- **Brave Search** - Web research (requires `BRAVE_API_KEY`)

### Network Security
Default firewall whitelist allows only:
- api.anthropic.com, anthropic.com, console.anthropic.com, statsig.anthropic.com (443)
- registry.npmjs.org (443)
- github.com (443, 22), objects.githubusercontent.com, raw.githubusercontent.com
- pypi.org, files.pythonhosted.org (443)
- DB_SERVER (1433)
- DNS (53)

Web access (ports 80/443 to all) is toggleable via `claude-web on`.

### CI/CD (.github/workflows/)
- **build.yml** - Builds and tests on push/PR, pushes to GHCR on main
- **update-check.yml** - Twice-daily (6:00/18:00 UTC) rebuild to track Claude Code npm releases

## Required Environment Variables

- `ANTHROPIC_API_KEY` - Claude API key (required unless using shared OAuth)

## Optional Environment Variables

- `DB_SERVER`, `DB_PORT` (default 1433), `DB_USERNAME`, `DB_PASSWORD`, `DB_DATABASE` - Database connection
- `BRAVE_API_KEY` - For Brave Search MCP server
- `CLAUDE_CPU_LIMIT` (default 4), `CLAUDE_MEM_LIMIT` (default 8g) - Resource limits
- `CLAUDE_WEB_ACCESS` (default off) - Initial web access state
- `CLAUDE_SHARE_AUTH` (default true) - Share host's `~/.claude` OAuth credentials
