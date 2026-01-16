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

# Show environment info
log_info "Claude Container starting..."
log_info "  DB_SERVER: ${DB_SERVER:-<not set>}"
log_info "  Web access: ${CLAUDE_WEB_ACCESS}"
log_info "  Working directory: $(pwd)"

# Check for authentication (API key OR OAuth credentials)
if [ -z "$ANTHROPIC_API_KEY" ] && [ ! -f "$HOME/.claude/.credentials.json" ]; then
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
