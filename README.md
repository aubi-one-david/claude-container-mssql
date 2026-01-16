# Claude Container with MSSQL (SQL Server) Database Tools

A secure Podman container for running Claude Code with `--dangerously-skip-permissions`. Network and filesystem isolation make permissionless mode safe, while providing pre-configured MSSQL database tools.

## Features

- **Network Isolation**: Firewall whitelist blocks unauthorized network access
- **MSSQL Ready**: Pre-configured with ODBC Driver 18, pyodbc, and go-sqlcmd
- **MCP Servers**: Filesystem, MSSQL, Memory, and Brave Search servers included
- **Session Persistence**: Full conversation transcripts auto-saved to git
- **Simple Interface**: Single wrapper script for all operations

## Quick Start

```bash
# 1. Clone the repository
git clone https://github.com/aubi-one-david/claude-container.git
cd claude-container

# 2. Set environment variables
export ANTHROPIC_API_KEY="your-api-key"

# Optional: Database connection (only if using MSSQL features)
# export DB_SERVER="your-sql-server"
# export DB_USERNAME="sa"
# export DB_PASSWORD="your-password"
# export DB_DATABASE="your-database"

# 3. Build and run
./claude-run.sh --build
./claude-run.sh /path/to/your/project
```

## Requirements

- **Podman** (or Docker with minor modifications)
- **ANTHROPIC_API_KEY** environment variable

## Usage

### Basic Commands

```bash
# Run Claude in current directory
./claude-run.sh

# Run in specific project
./claude-run.sh ../my-project

# Resume last session
./claude-run.sh -- --resume

# Get shell access to container
./claude-run.sh --shell

# Show status
./claude-run.sh --status
```

### Inside Container Commands

```bash
# Enable web access for research
claude-web on

# Disable web access
claude-web off

# Show container status
claude-status
```

### Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `ANTHROPIC_API_KEY` | Yes | - | Claude API key |
| `DB_SERVER` | No | - | SQL Server hostname |
| `DB_PORT` | No | 1433 | SQL Server port |
| `DB_USERNAME` | No | - | Database username |
| `DB_PASSWORD` | No | - | Database password |
| `DB_DATABASE` | No | - | Default database |
| `BRAVE_API_KEY` | No | - | Brave Search API key |
| `CLAUDE_CPU_LIMIT` | No | 4 | CPU cores limit |
| `CLAUDE_MEM_LIMIT` | No | 8g | Memory limit |
| `CLAUDE_WEB_ACCESS` | No | off | Initial web access state |
| `CLAUDE_SHARE_AUTH` | No | true | Share host's ~/.claude OAuth credentials |

## Network Security

The container runs with a strict firewall that only allows:

**Always Allowed:**
- api.anthropic.com (Claude API)
- github.com (git operations)
- registry.npmjs.org (npm packages)
- pypi.org (Python packages)
- Your DB_SERVER (database)

**Toggleable (via `claude-web on`):**
- All HTTP/HTTPS traffic

## MCP Servers

Four MCP servers are pre-configured:

| Server | Purpose | Env Vars Required |
|--------|---------|-------------------|
| **Filesystem** | File operations in /workspace | None |
| **MSSQL** | Database queries | DB_SERVER, DB_USERNAME, etc. |
| **Memory** | Cross-session knowledge | None |
| **Brave Search** | Web research | BRAVE_API_KEY (optional) |

## Session Persistence

Sessions are automatically saved to `.claude-sessions/` in your project:

```
.claude-sessions/
├── transcripts/
│   ├── 2026-01-13_143022.jsonl
│   └── 2026-01-14_091533.jsonl
└── index.json
```

Sessions are committed to git on container exit.

## Project Structure

```
claude-container/
├── Containerfile           # Container build definition
├── claude-run.sh           # Main entry point
├── scripts/
│   ├── entrypoint.sh       # Container entrypoint
│   ├── init-firewall.sh    # Firewall setup
│   ├── claude-web          # Web access toggle
│   ├── claude-status       # Status display
│   └── session-save.sh     # Session persistence hook
├── config/
│   ├── default-claude.md   # Default Claude context
│   └── mcp.json            # MCP server configuration
├── SPEC.md                 # Full specification
└── README.md               # This file
```

## Building

```bash
# Standard build
./claude-run.sh --build

# Clean rebuild
./claude-run.sh --build-no-cache

# Pull latest from GitHub Container Registry
podman pull ghcr.io/aubi-one-david/claude-container:latest
```

## Integrating with Your Project

1. Your project's `.claude/` directory is mounted and takes precedence
2. Existing hooks, agents, and prompts work automatically
3. Add project-specific MCP servers via `.mcp.json` in your project root

Example project structure:
```
my-project/
├── .claude/
│   ├── CLAUDE.md           # Project context
│   ├── agents/             # Custom agents
│   ├── hooks/              # Project hooks
│   └── settings.json       # Project settings
├── .claude-sessions/       # Auto-created for session storage
└── .mcp.json               # Project-specific MCP servers
```

## Security Notes

- Container runs as non-root user
- Network is restricted by iptables firewall
- API keys are passed at runtime, not baked into image
- `--dangerously-skip-permissions` is only safe due to container isolation

**Do not use this container with untrusted code** - the permissionless mode can execute arbitrary commands.

## License

MIT
