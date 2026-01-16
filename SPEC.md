# Claude Container Specification

**Project**: claude-container
**Target**: Podman container for running Claude Code with `--dangerously-skip-permissions`
**First Use Case**: MSSQL DataWarehouse development (industry-reporting-db_01)
**Version**: 1.0
**Date**: 2026-01-15

---

## 1. Executive Summary

This specification defines a lightweight, secure Podman container for running Claude Code in an isolated environment. The container provides:

- **Controlled autonomy**: `--dangerously-skip-permissions` with network isolation
- **Session persistence**: Full conversation transcripts tracked in git
- **Tool portability**: Transfer existing hooks, agents, and context between projects
- **Simple interface**: Single wrapper script for all operations

---

## 2. Design Principles

| Principle | Implementation |
|-----------|----------------|
| **Lightweight** | Minimal base image, only essential packages |
| **Secure** | Network firewall with explicit web access toggle |
| **Portable** | Git-tracked configuration and sessions |
| **Simple** | Single entry point wrapper script |
| **Maintainable** | Automated updates via GitHub Actions + Dependabot |

---

## 3. Container Architecture

### 3.1 Base Image

```
node:22-alpine (with multi-stage pyodbc build)
```

**Rationale**: Alpine with multi-stage build achieves smallest image size (352MB). pyodbc is compiled in a separate build stage to avoid shipping build tools.

**Alternative**: `Containerfile.debian` provides a Debian-based variant (619MB) if Alpine compatibility issues arise.

### 3.2 Installed Packages

#### System Packages (apt)
| Package | Purpose | Size Impact |
|---------|---------|-------------|
| `curl` | Downloads, health checks | ~300KB |
| `gnupg` | Microsoft repo key verification | ~2MB |
| `git` | Version control, session tracking | ~35MB |
| `msodbcsql18` | Microsoft ODBC Driver 18 | ~25MB |
| `unixodbc-dev` | ODBC driver manager | ~2MB |
| `iptables` | Network firewall rules | ~2MB |
| `jq` | JSON processing in scripts | ~1MB |

#### Go Tools (single binary)
| Tool | Purpose | Size Impact |
|------|---------|-------------|
| `go-sqlcmd` | Modern SQL Server CLI | ~15MB |

#### Node.js (for Claude Code)
| Package | Purpose | Size Impact |
|---------|---------|-------------|
| `nodejs` (20.x LTS) | Claude Code runtime | ~90MB |
| `npm` | Package management | included |
| `@anthropic-ai/claude-code` | Claude Code CLI | ~50MB |

#### Python Packages (pip)
| Package | Purpose | Notes |
|---------|---------|-------|
| `pyodbc` | MSSQL connectivity | Production-ready |
| `mssql-python` | (Future) Microsoft driver | For evaluation |

**Actual Image Size**: 352MB (Alpine), 619MB (Debian)

### 3.3 Directory Structure

```
/home/claude/                    # Container user home
├── .claude/                     # Claude Code user config (persistent)
│   ├── settings.json
│   ├── CLAUDE.md
│   └── projects/                # Session transcripts
│       └── <project-hash>/
│           └── *.jsonl          # Conversation files
│
/workspace/                      # Mounted project directory
├── .claude/                     # Project config (from git)
│   ├── settings.json            # Team settings
│   ├── settings.local.json      # Personal settings
│   ├── CLAUDE.md                # Project memory
│   ├── agents/                  # Custom agents
│   ├── hooks/                   # Hook scripts
│   └── prompts/                 # Task templates
├── .claude-sessions/            # Git-tracked sessions (NEW)
│   ├── transcripts/             # Full conversation JSON
│   └── summaries/               # Compacted summaries
└── .mcp.json                    # MCP server config
```

---

## 4. Network Security

### 4.1 Firewall Architecture

**Default Mode**: Strict whitelist (DROP all, ACCEPT specific)

```
┌─────────────────────────────────────────────────────────┐
│                    Container Network                     │
├─────────────────────────────────────────────────────────┤
│  ALLOWED (always):                                      │
│  ├── api.anthropic.com (443)    # Claude API           │
│  ├── registry.npmjs.org (443)   # npm packages         │
│  ├── github.com (443)           # git operations       │
│  ├── objects.githubusercontent.com (443) # GitHub raw  │
│  └── <DB_SERVER> (1433)         # Database server     │
│                                                         │
│  ALLOWED (when web toggle ON):                          │
│  └── * (80, 443)                # All HTTP/HTTPS       │
│                                                         │
│  BLOCKED (always):                                      │
│  └── Everything else                                    │
└─────────────────────────────────────────────────────────┘
```

### 4.2 Web Access Toggle

**Command**: `claude-web on|off|status`

```bash
# Enable web research (creates time-limited exception)
claude-web on          # Enables for current session
claude-web on 30m      # Enables for 30 minutes
claude-web off         # Disables immediately
claude-web status      # Shows current state
```

**Implementation**: Modifies iptables rules at runtime via sudo without password for the specific rule.

---

## 5. Session Persistence Strategy

### 5.1 Git-Tracked Sessions

**Location**: `/workspace/.claude-sessions/`

**Structure**:
```
.claude-sessions/
├── .gitignore           # Exclude temp files
├── transcripts/
│   ├── 2026-01-13_001.jsonl
│   ├── 2026-01-13_002.jsonl
│   └── ...
└── index.json           # Session metadata
```

### 5.2 Session Lifecycle

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  Session    │     │  Working    │     │  Commit     │
│  Start      │────▶│  Session    │────▶│  Session    │
└─────────────┘     └─────────────┘     └─────────────┘
      │                   │                   │
      ▼                   ▼                   ▼
 Load previous      Claude Code         Auto-commit
 session if         writes to           on session
 exists             transcript          end hook
```

### 5.3 SessionEnd Hook

Automatically commits session on exit:

```bash
#!/bin/bash
# .claude/hooks/session-save.sh
cd "$CLAUDE_PROJECT_DIR"
if [ -d ".claude-sessions" ]; then
    git add .claude-sessions/
    git commit -m "chore(session): save Claude session $(date +%Y-%m-%d_%H%M)" \
        --author="Claude <claude@container>" \
        --no-verify 2>/dev/null || true
fi
```

---

## 6. Hook Transfer Strategy

### 6.1 Source Project Hooks (industry-reporting-db_01)

| Hook | Event | Purpose |
|------|-------|---------|
| `startup-context.sh` | SessionStart | Load TODO.md status |
| `bash-reminder.sh` | PreToolUse | Remind about run_sql.sh |
| `parallel-reminder.sh` | UserPromptSubmit | Remind about parallel tasks |

### 6.2 Container-Specific Hooks

| Hook | Event | Purpose |
|------|-------|---------|
| `session-save.sh` | SessionEnd | Git-commit session |
| `web-access-log.sh` | PreToolUse | Log web fetch attempts |
| `firewall-check.sh` | SessionStart | Verify firewall is active |

### 6.3 Hook Composition

Project hooks are copied into the container at mount time. Container hooks wrap project hooks:

```
Container Hook (session-start.sh)
├── Run firewall-check.sh
├── Run project's startup-context.sh (if exists)
└── Load session state
```

---

## 7. Agent Transfer Strategy

### 7.1 Source Project Agents

| Agent | Model | Specialty |
|-------|-------|-----------|
| `mssql-architect.md` | Sonnet | Database design |
| `mssql-refactoring-specialist.md` | Haiku | Schema migrations |
| `mssql-tester.md` | Sonnet | Testing, tSQLt |

### 7.2 Container Approach

Agents are **project-specific** and remain in the project's `.claude/agents/` directory. The container mounts this directory read-write, so agents work without modification.

**No container-level agents needed** - agents are a project concern.

---

## 8. Context Management

### 8.1 Context Hierarchy (in container)

```
Priority (highest to lowest):
1. /workspace/.claude/CLAUDE.md        # Project memory
2. /workspace/.claude/rules/*.md       # Project rules
3. /home/claude/.claude/CLAUDE.md      # Container defaults (minimal)
4. /workspace/CLAUDE.md                # Root project memory
```

### 8.2 Container Default Context

`/home/claude/.claude/CLAUDE.md` (minimal, generic):

```markdown
# Claude Container Defaults

## Environment
- Running in isolated Podman container
- Network restricted to whitelist (use `claude-web on` for research)
- Sessions auto-saved to .claude-sessions/ on exit

## Available Tools
- go-sqlcmd: SQL Server CLI
- pyodbc: Python MSSQL driver
- git: Version control

## Container Commands
- `claude-web on/off`: Toggle internet access
- `claude-status`: Show container state
```

### 8.3 Keeping Context Updated

Project context (`/workspace/.claude/`) is mounted from host, so updates to context files on the host are immediately visible in the container.

---

## 9. Interface Design

### 9.1 Primary Entry Point

**Script**: `claude-run.sh`

```bash
#!/bin/bash
# Usage: ./claude-run.sh [project-path] [claude-args...]
#
# Examples:
#   ./claude-run.sh                           # Current directory
#   ./claude-run.sh ../industry-reporting-db_01
#   ./claude-run.sh . --resume                # Resume last session
```

### 9.2 Command Reference

| Command | Purpose |
|---------|---------|
| `./claude-run.sh` | Start Claude (auto-pulls latest image) |
| `./claude-run.sh --no-pull` | Start without pulling (fast startup) |
| `./claude-run.sh --build` | Rebuild container image locally |
| `./claude-run.sh --shell` | Get bash shell in container |
| `./claude-run.sh --status` | Show container/session status |
| `claude-web on\|off` | (Inside container) Toggle web access |

### 9.3 Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `GITHUB_USERNAME` | - | GitHub username for GHCR image |
| `CLAUDE_CONTAINER_IMAGE` | `ghcr.io/$GITHUB_USERNAME/claude-container:latest` | Container image override |
| `CLAUDE_AUTO_PULL` | `true` | Auto-pull latest image on startup |
| `CLAUDE_SHARE_AUTH` | `true` | Share host's `~/.claude` for OAuth credentials |
| `ANTHROPIC_API_KEY` | (required*) | Claude API key |
| `DB_SERVER` | - | Database server hostname |
| `DB_PORT` | `1433` | Database server port |

**Authentication**: Either `ANTHROPIC_API_KEY` or shared OAuth credentials (`~/.claude/.credentials.json`) is required. When `CLAUDE_SHARE_AUTH=true` (default), the host's `~/.claude` directory is mounted with user namespace mapping to preserve file permissions.

**Note**: `GITHUB_USERNAME` and other credentials can be set in `../.env` which is auto-sourced by `claude-run.sh`.

### 9.4 Container Naming

**Format**: `claude_<project>_<HH-MM-SS>`

Each container instance gets a unique name based on:
- `claude_` prefix for easy identification
- Project directory name (sanitized: spaces → underscores, special chars removed)
- Timestamp in HH-MM-SS format

**Examples**:
```
claude_my-project_14-32-05
claude_industry-reporting-db_01_09-15-33
claude_claude-container_16-45-00
```

**Benefits**:
- Run multiple instances simultaneously on different projects
- Easy identification with `podman ps`
- Automatic cleanup with `--rm` flag (no name conflicts)

**Sanitization Rules**:
- Spaces replaced with underscores
- Invalid characters removed (only alphanumeric, dash, underscore, dot allowed)
- Long project names truncated to 40 characters

---

## 10. Update Strategy

### 10.1 Automated Updates

**GitHub Actions** workflow runs **twice daily** (6:00 and 18:00 UTC):

1. Check for new Claude Code version (releases are nearly daily)
2. Build and test the image
3. Push to GHCR with `:latest` and `:daily-N` tags
4. Image label includes `claude.code.version` for tracking

```
Twice daily cron (6:00 & 18:00 UTC)
         │
         ▼
┌─────────────────────────────┐
│ 1. Check Claude Code version│
│ 2. Build image              │
│ 3. Run tests                │
│ 4. Push to GHCR             │
│    - :latest (always)       │
│    - :daily-N (audit trail) │
└─────────────────────────────┘
```

**Dependabot** monitors:
- GitHub Actions versions
- Base image updates

### 10.2 Image Tags

| Tag | Purpose | Updated |
|-----|---------|---------|
| `:latest` | Most current build | Twice daily |
| `:daily-N` | Audit trail / rollback | Each build |
| `:v1.0` | Stable releases | Manual tag |
| `:main` | Latest from main branch | On push |

### 10.3 Local Usage

```bash
# Normal use - auto-pulls latest on startup
./claude-run.sh

# Skip pull for fast/offline startup
./claude-run.sh --no-pull

# Force pull manually
./claude-run.sh --pull

# Rebuild locally (development)
./claude-run.sh --build --no-cache
```

---

## 11. GitHub Integration

### 11.1 Repository Structure

```
claude-container/
├── .github/
│   ├── workflows/
│   │   ├── build.yml           # CI build on PR/push to main
│   │   ├── release.yml         # Build and push on version tag (v*)
│   │   └── update-check.yml    # Twice-daily auto-push to :latest
│   └── dependabot.yml          # Automated security updates
├── Containerfile               # Podman/Docker build file
├── claude-run.sh               # Entry point script
├── scripts/
│   ├── init-firewall.sh        # Network setup
│   ├── claude-web.sh           # Web access toggle
│   └── session-hooks/          # Container hooks
├── config/
│   ├── odbc.ini                # ODBC configuration
│   └── default-claude.md       # Default container context
├── SPEC.md                     # This document
└── README.md                   # User documentation
```

### 11.2 GitHub Free Tier Usage

| Feature | Usage | Limit |
|---------|-------|-------|
| GitHub Actions | CI/CD builds | Unlimited (public repo) |
| GHCR | Container registry | Unlimited storage |
| Releases | Version artifacts | 2GB per file |
| Dependabot | Security updates | Free |

---

## 12. Security Considerations

### 12.1 Threat Model

| Threat | Mitigation |
|--------|------------|
| Malicious code execution | Network firewall blocks exfiltration |
| Credential theft | API key passed at runtime, not baked in |
| Session data leakage | Sessions committed to private/controlled repo |
| Supply chain attack | Dependabot + pinned versions |

### 12.2 What `--dangerously-skip-permissions` Allows

- File read/write without prompts
- Bash execution without prompts
- Tool usage without confirmation

### 12.3 What the Container Restricts

- Network access (firewall whitelist)
- Host filesystem access (only mounted workspace)
- System modifications (non-root user)

---

## 13. Testing Plan

### 13.1 Build Verification

- [ ] Container builds successfully
- [ ] Claude Code starts and can authenticate
- [ ] go-sqlcmd connects to test database
- [ ] pyodbc connects to test database

### 13.2 Network Security

- [ ] Cannot reach arbitrary URLs by default
- [ ] Can reach api.anthropic.com
- [ ] Can reach MSSQL host
- [ ] `claude-web on` enables general web access
- [ ] `claude-web off` disables web access

### 13.3 Session Persistence

- [ ] Session transcripts saved to .claude-sessions/
- [ ] Sessions auto-commit on exit
- [ ] Sessions can be resumed across container restarts

### 13.4 Hook Transfer

- [ ] Project hooks from industry-reporting-db_01 work
- [ ] Container hooks execute correctly
- [ ] Hook composition works (container + project)

### 13.5 MCP Server Verification

- [ ] Filesystem MCP: Can list/read/write files in /workspace
- [ ] Filesystem MCP: Cannot access files outside /workspace
- [ ] MSSQL MCP: Can connect and list tables
- [ ] MSSQL MCP: Can execute SELECT queries
- [ ] Memory MCP: Can store and recall memories
- [ ] Memory MCP: Memories persist across container restarts
- [ ] Brave Search MCP: Can perform web searches (with API key)

### 13.6 Driver Evaluation (Future)

- [ ] mssql-python basic connectivity
- [ ] mssql-python vs pyodbc performance comparison
- [ ] mssql-python bulk operations

---

## 14. Resolved Design Decisions

| Question | Decision | Rationale |
|----------|----------|-----------|
| **Session cleanup** | Indefinite retention | Manual cleanup; sessions are valuable audit trail |
| **Multi-project** | Yes (unique names) | Container name: `claude_<project>_<HH-MM-SS>` enables concurrent instances |
| **Resource limits** | Soft defaults | 4 CPU, 8GB RAM default; overridable via env vars |
| **Base image** | Alpine (multi-stage) | 352MB vs 619MB Debian; multi-stage build avoids gcompat issues |
| **Update frequency** | Twice daily | Claude Code releases nearly daily; `:latest` always current |
| **Auto-pull** | On by default | Ensures users always have latest Claude Code |

---

## 15. MCP Server Configuration

All four MCP servers are pre-configured in the container for maximum capability.

### 15.1 Pre-Configured MCP Servers

| Server | Size | Transport | Purpose |
|--------|------|-----------|---------|
| **Filesystem** | 20-50 KB | stdio | Access-controlled file operations |
| **MSSQL** | 6-8 KB | stdio | Safe LLM database queries |
| **Memory** | 50-100 KB | stdio | Cross-session knowledge persistence |
| **Brave Search** | 2-5 MB | stdio | Web research (requires API key) |

### 15.2 MCP Configuration File

Pre-configured in container at `/home/claude/.mcp.json`:

```json
{
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/workspace"],
      "env": {}
    },
    "mssql": {
      "command": "uvx",
      "args": ["mssql-mcp-server"],
      "env": {
        "MSSQL_HOST": "${DB_SERVER}",
        "MSSQL_USER": "${DB_USERNAME}",
        "MSSQL_PASSWORD": "${DB_PASSWORD}",
        "MSSQL_DATABASE": "${DB_DATABASE}"
      }
    },
    "memory": {
      "command": "npx",
      "args": ["-y", "mcp-memory-keeper"],
      "env": {}
    },
    "brave-search": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-brave-search"],
      "env": {
        "BRAVE_API_KEY": "${BRAVE_API_KEY}"
      }
    }
  }
}
```

### 15.3 MCP Server Details

**Filesystem MCP** (`@modelcontextprotocol/server-filesystem`)
- Official Anthropic server
- Provides: read_file, write_file, list_directory, search_files
- Access restricted to `/workspace` (mounted project)
- Adds static access control beyond built-in file tools

**MSSQL MCP** (`mssql-mcp-server`)
- Community Python package (6-8 KB)
- Provides: query, list_tables, describe_table
- Uses pyodbc underneath (requires ODBC driver)
- Safer than raw SQL execution - can restrict to read-only

**Memory MCP** (`mcp-memory-keeper`)
- Community TypeScript package
- Provides: store_memory, recall_memory, search_memories
- SQLite-backed persistent knowledge graph
- Preserves insights across container restarts

**Brave Search MCP** (`@modelcontextprotocol/server-brave-search`)
- Official Brave server
- Provides: web_search, local_search, news_search
- Free tier: 2,000 requests/month
- Alternative to `claude-web on` for structured search

### 15.4 Environment Variables for MCP

| Variable | Required | Purpose |
|----------|----------|---------|
| `DB_SERVER` | Yes | Database server for MSSQL MCP |
| `DB_USERNAME` | Yes | Database username |
| `DB_PASSWORD` | Yes | Database password |
| `DB_DATABASE` | Yes | Default database |
| `BRAVE_API_KEY` | Optional | For Brave Search (free tier available) |

---

## 16. Base Image Analysis

### 16.1 Alpine vs Debian - Final Results

| Factor | Alpine (multi-stage) | Debian Slim |
|--------|---------------------|-------------|
| **Final image size** | **352 MB** ✓ | 619 MB |
| Base image | node:22-alpine | python:3.12-slim-bookworm |
| pyodbc installation | Compiled in build stage | pip install |
| ODBC Driver | msodbcsql18 APK | msodbcsql18 deb |
| sqlcmd | mssql-tools18 (included) | go-sqlcmd (separate) |

**Key insight**: Multi-stage build is the solution:
1. Build stage: Install gcc/g++, compile pyodbc wheel
2. Final stage: Copy only the wheel, no build tools
3. Result: Alpine is 43% smaller than Debian

### 16.2 Multi-Stage Build Strategy

```dockerfile
# Stage 1: Build pyodbc
FROM python:3.12-alpine AS pyodbc-builder
RUN apk add gcc g++ musl-dev unixodbc-dev
RUN pip wheel pyodbc

# Stage 2: Runtime (no build tools)
FROM node:22-alpine AS final
COPY --from=pyodbc-builder /wheels/*.whl /wheels/
RUN pip install /wheels/*.whl && rm -rf /wheels
```

### 16.3 Debian Variant

`Containerfile.debian` is preserved as a fallback if Alpine compatibility issues arise. Use with:
```bash
podman build -t claude-container:debian -f Containerfile.debian .
```

---

## 17. Resource Limits

### 17.1 Default Limits

```bash
# Soft defaults (overridable)
CLAUDE_CPU_LIMIT="${CLAUDE_CPU_LIMIT:-4}"
CLAUDE_MEM_LIMIT="${CLAUDE_MEM_LIMIT:-8g}"
```

### 17.2 Podman Resource Flags

```bash
podman run \
    --cpus="${CLAUDE_CPU_LIMIT}" \
    --memory="${CLAUDE_MEM_LIMIT}" \
    ...
```

### 17.3 Override Examples

```bash
# High-performance mode
CLAUDE_CPU_LIMIT=8 CLAUDE_MEM_LIMIT=16g ./claude-run.sh

# Resource-constrained mode
CLAUDE_CPU_LIMIT=2 CLAUDE_MEM_LIMIT=4g ./claude-run.sh
```

---

## 18. Implementation Phases

### Phase 1: Core Container
- Containerfile with base packages (Debian slim + ODBC + Node.js)
- claude-run.sh wrapper script
- Basic firewall setup (iptables whitelist)
- Session persistence hooks (SessionEnd auto-commit)
- Resource limit defaults (4 CPU, 8GB RAM)

### Phase 2: MCP Integration
- Configure all 4 MCP servers (Filesystem, MSSQL, Memory, Brave)
- Test MCP server functionality
- Document MCP environment variables

### Phase 3: Project Integration
- Transfer hooks from industry-reporting-db_01
- Test with real DataWarehouse project
- Refine firewall rules for project needs
- Validate session git-tracking workflow

### Phase 4: Automation
- GitHub Actions CI/CD
- GHCR publishing
- Dependabot configuration
- Weekly update checks

### Phase 5: Evaluation
- mssql-python driver testing (compare to pyodbc)
- Performance benchmarks
- Documentation refinement

---

## Appendix A: Reference Commands

```bash
# Build container
podman build -t claude-container -f Containerfile .

# Run interactively
podman run -it --rm \
    -v $(pwd):/workspace:Z \
    -v claude-home:/home/claude/.claude:Z \
    -e ANTHROPIC_API_KEY \
    -e DB_SERVER \
    --cap-add NET_ADMIN \
    claude-container

# Run with web access
podman run -it --rm \
    -v $(pwd):/workspace:Z \
    -e CLAUDE_WEB_ACCESS=on \
    ...
```

---

## Appendix B: Firewall Rules

```bash
#!/bin/bash
# init-firewall.sh

# Default policy: DROP
iptables -P OUTPUT DROP

# Allow loopback
iptables -A OUTPUT -o lo -j ACCEPT

# Allow established connections
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow DNS
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT

# Allow Claude API
iptables -A OUTPUT -d api.anthropic.com -p tcp --dport 443 -j ACCEPT

# Allow npm registry
iptables -A OUTPUT -d registry.npmjs.org -p tcp --dport 443 -j ACCEPT

# Allow GitHub
iptables -A OUTPUT -d github.com -p tcp --dport 443 -j ACCEPT
iptables -A OUTPUT -d objects.githubusercontent.com -p tcp --dport 443 -j ACCEPT

# Allow MSSQL (from env var)
if [ -n "$DB_SERVER" ]; then
    iptables -A OUTPUT -d "$DB_SERVER" -p tcp --dport "${DB_PORT:-1433}" -j ACCEPT
fi
```

---

## Appendix C: Session Save Hook

```bash
#!/bin/bash
# session-save.sh - SessionEnd hook

set -e

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-/workspace}"
SESSION_DIR="$PROJECT_DIR/.claude-sessions"
TRANSCRIPT_DIR="$SESSION_DIR/transcripts"

# Create directories if needed
mkdir -p "$TRANSCRIPT_DIR"

# Find and copy current session transcript
CLAUDE_SESSION_DIR="$HOME/.claude/projects"
if [ -d "$CLAUDE_SESSION_DIR" ]; then
    # Find most recent session file
    LATEST=$(find "$CLAUDE_SESSION_DIR" -name "*.jsonl" -mmin -60 -type f | head -1)
    if [ -n "$LATEST" ]; then
        TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)
        cp "$LATEST" "$TRANSCRIPT_DIR/${TIMESTAMP}.jsonl"
    fi
fi

# Git commit if in a repo
if git -C "$PROJECT_DIR" rev-parse --git-dir > /dev/null 2>&1; then
    cd "$PROJECT_DIR"
    git add .claude-sessions/ 2>/dev/null || true
    git commit -m "chore(session): auto-save $(date +%Y-%m-%d_%H:%M)" \
        --author="Claude Container <claude@container.local>" \
        --no-verify 2>/dev/null || true
fi

exit 0
```
