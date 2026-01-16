# Claude Container Defaults

You are running inside a secure Claude Container with network isolation.

## Environment

- **Container**: Podman-based, running with `--dangerously-skip-permissions`
- **Network**: Restricted to whitelist by default
- **Sessions**: Auto-saved to `.claude-sessions/` on exit

## Available Tools

### Database
- `sqlcmd` - Go-based SQL Server CLI (go-sqlcmd)
- `pyodbc` - Python MSSQL driver via ODBC Driver 18
- MSSQL MCP server available for safe queries

### Development
- `git` - Version control
- `python` - Python 3.12 with pyodbc
- `node` / `npm` - Node.js 20 LTS

### Container Commands
Run these from the terminal:
- `claude-web on` - Enable internet access for research
- `claude-web off` - Disable internet (whitelist only)
- `claude-web status` - Show current network mode
- `claude-status` - Show full container status

## MCP Servers Available

1. **Filesystem** - Access-controlled file operations within /workspace
2. **MSSQL** - Safe database queries (requires DB_* env vars)
3. **Memory** - Persistent knowledge across sessions
4. **Brave Search** - Web research (requires BRAVE_API_KEY)

## Network Whitelist (always allowed)

- api.anthropic.com (Claude API)
- github.com (git operations)
- registry.npmjs.org (npm)
- pypi.org (Python packages)
- $DB_SERVER (your database)

Use `claude-web on` to temporarily enable access to other sites.

## Session Persistence

Sessions are saved to `.claude-sessions/transcripts/` in the project directory.
They are automatically committed to git on session end.
