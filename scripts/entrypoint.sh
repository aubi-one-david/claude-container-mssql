#!/bin/bash
# Claude Container Entrypoint
# Initializes firewall and starts Claude Code

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Initialize firewall
log_info "Initializing network firewall..."
if /home/claude/.local/bin/init-firewall.sh; then
    log_info "Firewall initialized successfully"
else
    log_warn "Firewall initialization failed - running without network restrictions"
fi

# Ensure session directory exists (Claude Code writes session data here)
mkdir -p "$HOME/.claude/projects"

# Show environment info
log_info "Claude Container starting..."
log_info "  DB_SERVER: ${DB_SERVER:-<not set>}"
log_info "  Web access: ${CLAUDE_WEB_ACCESS}"
log_info "  Working directory: $(pwd)"

# Skip auth check for non-interactive commands (version checks, tool tests)
needs_auth=true
for arg in "$@"; do
    case "$arg" in
        --version|--help|-v|-h)
            needs_auth=false
            break
            ;;
    esac
done

# Also skip auth when the command is not claude itself (e.g. sqlcmd, python)
case "$1" in
    claude|/usr/local/bin/claude) ;;
    *) needs_auth=false ;;
esac

# Check for authentication (API key OR OAuth credentials)
if [ "$needs_auth" = true ] && [ -z "$ANTHROPIC_API_KEY" ] && [ ! -f "$HOME/.claude/.credentials.json" ]; then
    log_error "No authentication found"
    log_error "Set ANTHROPIC_API_KEY or mount ~/.claude with OAuth credentials"
    exit 1
fi

if [ -n "$ANTHROPIC_API_KEY" ]; then
    log_info "  Auth: API key"
else
    log_info "  Auth: OAuth (from ~/.claude)"
fi

# Run session start hooks if they exist
if [ -f "/workspace/.claude/hooks/session-start.sh" ]; then
    log_info "Running project session-start hook..."
    bash /workspace/.claude/hooks/session-start.sh || true
fi

# Execute the command (default: claude --dangerously-skip-permissions)
exec "$@"
