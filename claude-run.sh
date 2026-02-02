#!/bin/bash
# Claude Container Runner
# Usage: ./claude-run.sh [project-path] [options] [-- claude-args...]
#
# Examples:
#   ./claude-run.sh                              # Run in current directory
#   ./claude-run.sh ../my-project                # Run in specific project
#   ./claude-run.sh --build                      # Rebuild container image
#   ./claude-run.sh --shell                      # Get bash shell in container
#   ./claude-run.sh . -- --resume               # Pass args to Claude

# Allow sourcing for testing without executing (must be first)
if [ "${1:-}" = "--source-only" ]; then
    # Define only the function needed for testing
    generate_container_name() {
        local project_path="$1"
        local project_name
        project_name=$(basename "$project_path")
        project_name=$(echo "$project_name" | tr ' ' '_' | tr -cd 'a-zA-Z0-9_.-')
        project_name="${project_name:0:40}"
        local timestamp
        timestamp=$(date +%H-%M-%S)
        echo "claude_${project_name}_${timestamp}"
    }
    return 0 2>/dev/null || exit 0
fi

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source credentials from parent directory if available
if [ -f "$SCRIPT_DIR/../.env" ]; then
    source "$SCRIPT_DIR/../.env"
fi

# Set image name: prefer env var, then GHCR with username, then local
if [ -n "$CLAUDE_CONTAINER_IMAGE" ]; then
    IMAGE_NAME="$CLAUDE_CONTAINER_IMAGE"
elif [ -n "$GITHUB_USERNAME" ]; then
    IMAGE_NAME="ghcr.io/${GITHUB_USERNAME}/claude-container:latest"
else
    IMAGE_NAME="claude-container:latest"
fi

AUTO_PULL="${CLAUDE_AUTO_PULL:-true}"  # Pull by default
SHARE_AUTH="${CLAUDE_SHARE_AUTH:-true}"  # Share host's ~/.claude by default
NEW_SESSION="false"  # Resume by default

# Default resource limits
CPU_LIMIT="${CLAUDE_CPU_LIMIT:-4}"
MEM_LIMIT="${CLAUDE_MEM_LIMIT:-8g}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Generate unique container name: claude_<project>_<HH-MM-SS>
generate_container_name() {
    local project_path="$1"
    local project_name

    # Extract directory name from path
    project_name=$(basename "$project_path")

    # Sanitize: replace spaces with underscores, remove invalid chars
    # Podman container names can contain: [a-zA-Z0-9][a-zA-Z0-9_.-]*
    project_name=$(echo "$project_name" | tr ' ' '_' | tr -cd 'a-zA-Z0-9_.-')

    # Truncate to reasonable length (leave room for prefix and timestamp)
    # Format: claude_<name>_HH-MM-SS = 7 + name + 9 = 16 + name
    # Keep name under 40 chars for safety
    project_name="${project_name:0:40}"

    # Generate timestamp
    local timestamp
    timestamp=$(date +%H-%M-%S)

    echo "claude_${project_name}_${timestamp}"
}

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

show_help() {
    cat << 'EOF'
Claude Container Runner

USAGE:
    ./claude-run.sh [OPTIONS] [PROJECT_PATH] [-- CLAUDE_ARGS...]

OPTIONS:
    --build           Build/rebuild the container image locally
    --build-no-cache  Rebuild without cache
    --no-pull         Skip automatic image pull (default: pulls latest)
    --pull            Force pull latest image from registry
    --no-share-auth   Don't mount host's ~/.claude (use isolated auth)
    --shell           Start bash shell instead of Claude
    --new             Start a new session (don't resume previous)
    --status          Show container and environment status
    --help            Show this help message

ENVIRONMENT VARIABLES:
    GITHUB_USERNAME       GitHub username for GHCR image (ghcr.io/$USER/claude-container)
    CLAUDE_CONTAINER_IMAGE  Override image name (default: ghcr.io/$GITHUB_USERNAME/claude-container:latest)
    CLAUDE_AUTO_PULL      Auto-pull on startup: true|false (default: true)
    CLAUDE_SHARE_AUTH     Share host credentials and settings from ~/.claude (default: true)
    ANTHROPIC_API_KEY     Claude API key (or use shared OAuth from ~/.claude)

    DB_SERVER             Database server hostname
    DB_PORT               Database server port (default: 1433)
    DB_USERNAME           Database username
    DB_PASSWORD           Database password
    DB_DATABASE           Default database name

    BRAVE_API_KEY         Brave Search API key (optional, for web search MCP)
    CLAUDE_CPU_LIMIT      CPU limit (default: 4)
    CLAUDE_MEM_LIMIT      Memory limit (default: 8g)
    CLAUDE_WEB_ACCESS     Initial web access state: on|off (default: off)

EXAMPLES:
    # Run Claude in current directory
    ./claude-run.sh

    # Run in specific project with web access enabled
    CLAUDE_WEB_ACCESS=on ./claude-run.sh ../my-project

    # Resume last session
    ./claude-run.sh -- --resume

    # High resource mode
    CLAUDE_CPU_LIMIT=8 CLAUDE_MEM_LIMIT=16g ./claude-run.sh

EOF
}

build_image() {
    local no_cache=""
    [ "$1" = "--no-cache" ] && no_cache="--no-cache"

    log_info "Building container image: $IMAGE_NAME"
    podman build $no_cache -t "$IMAGE_NAME" -f "$SCRIPT_DIR/Containerfile" "$SCRIPT_DIR"
    log_info "Build complete"
}

pull_image() {
    log_info "Pulling latest image..."
    podman pull "$IMAGE_NAME"
}

show_status() {
    echo -e "${BLUE}=== Claude Container Environment ===${NC}"
    echo ""
    echo "Image: $IMAGE_NAME"
    echo "Auto-pull: $AUTO_PULL"
    echo "Share auth: $SHARE_AUTH (host ~/.claude: $([ -d "$HOME/.claude" ] && echo "exists" || echo "not found"))"
    echo "CPU Limit: $CPU_LIMIT"
    echo "Memory Limit: $MEM_LIMIT"
    echo ""
    echo -e "${GREEN}Environment Variables:${NC}"
    echo "  ANTHROPIC_API_KEY: ${ANTHROPIC_API_KEY:+<set>}${ANTHROPIC_API_KEY:-<NOT SET - REQUIRED>}"
    echo "  DB_SERVER: ${DB_SERVER:-<not set>}"
    echo "  DB_PORT: ${DB_PORT:-1433}"
    echo "  DB_USERNAME: ${DB_USERNAME:-<not set>}"
    echo "  DB_DATABASE: ${DB_DATABASE:-<not set>}"
    echo "  BRAVE_API_KEY: ${BRAVE_API_KEY:+<set>}${BRAVE_API_KEY:-<not set>}"
    echo "  CLAUDE_WEB_ACCESS: ${CLAUDE_WEB_ACCESS:-off}"
    echo ""

    if podman image exists "$IMAGE_NAME" 2>/dev/null; then
        echo -e "${GREEN}Image Status:${NC} Available"
        podman image inspect "$IMAGE_NAME" --format '  Created: {{.Created}}' 2>/dev/null || true
        podman image inspect "$IMAGE_NAME" --format '  Size: {{.Size}}' 2>/dev/null || true
    else
        echo -e "${YELLOW}Image Status:${NC} Not built (run --build first)"
    fi
}

run_container() {
    local project_path="$1"
    shift
    local cmd=("$@")

    # Resolve project path
    if [ -z "$project_path" ]; then
        project_path="$(pwd)"
    else
        project_path="$(cd "$project_path" && pwd)"
    fi

    log_info "Project: $project_path"

    # Auto-pull if enabled and using a registry image
    if [ "$AUTO_PULL" = "true" ] && [[ "$IMAGE_NAME" == *"/"* ]]; then
        log_info "Pulling latest image: $IMAGE_NAME"
        if podman pull "$IMAGE_NAME" 2>/dev/null; then
            log_info "Image updated"
        else
            log_warn "Pull failed, using cached image if available"
        fi
    fi

    # Check if image exists (after potential pull)
    if ! podman image exists "$IMAGE_NAME" 2>/dev/null; then
        if [[ "$IMAGE_NAME" == *"/"* ]]; then
            log_error "Image not found: $IMAGE_NAME"
            log_error "Check your GITHUB_USERNAME or CLAUDE_CONTAINER_IMAGE setting"
            exit 1
        else
            log_warn "Container image not found, building..."
            build_image
        fi
    fi

    # Create session directory if it doesn't exist
    mkdir -p "$project_path/.claude-sessions/transcripts"

    # Generate unique container name
    local container_name
    container_name=$(generate_container_name "$project_path")

    # Default command if none provided
    if [ ${#cmd[@]} -eq 0 ]; then
        if [ "$NEW_SESSION" = "true" ]; then
            cmd=("claude" "--dangerously-skip-permissions")
        else
            cmd=("claude" "--dangerously-skip-permissions" "--resume")
        fi
    fi

    # Determine auth volume mounts and user mapping
    # Mount individual files instead of whole ~/.claude to prevent cache pollution
    # (session data, debug logs, file-history stay inside the container)
    local auth_mounts=()
    local user_flags=""
    local env_args=(
        -e "CLAUDE_WEB_ACCESS=${CLAUDE_WEB_ACCESS:-off}"
    )

    if [ "$SHARE_AUTH" = "true" ] && [ -d "$HOME/.claude" ]; then
        # Map host user to container user for file permissions
        user_flags="--userns=keep-id --user $(id -u):$(id -g)"

        # Check what auth is available
        if [ -f "$HOME/.claude/.credentials.json" ]; then
            log_info "  Auth: OAuth (from ~/.claude)"
            auth_mounts+=(-v "$HOME/.claude/.credentials.json:/home/claude/.claude/.credentials.json:ro")
        elif [ -n "$ANTHROPIC_API_KEY" ]; then
            log_info "  Auth: API key"
            env_args+=(-e "ANTHROPIC_API_KEY")
        else
            log_error "No authentication found"
            log_error "Run 'claude /login' for OAuth or set ANTHROPIC_API_KEY"
            exit 1
        fi

        # Mount user settings read-only if they exist on host
        [ -f "$HOME/.claude/settings.json" ] && \
            auth_mounts+=(-v "$HOME/.claude/settings.json:/home/claude/.claude/settings.json:ro")
        [ -f "$HOME/.claude/settings.local.json" ] && \
            auth_mounts+=(-v "$HOME/.claude/settings.local.json:/home/claude/.claude/settings.local.json:ro")
    else
        auth_mounts+=(-v "claude-home:/home/claude/.claude:Z")
        if [ -n "$ANTHROPIC_API_KEY" ]; then
            log_info "  Auth: API key (isolated)"
            env_args+=(-e "ANTHROPIC_API_KEY")
        else
            log_error "ANTHROPIC_API_KEY required with --no-share-auth"
            exit 1
        fi
    fi

    # Optional database variables
    [ -n "$DB_SERVER" ] && env_args+=(-e "DB_SERVER")
    [ -n "$DB_PORT" ] && env_args+=(-e "DB_PORT")
    [ -n "$DB_USERNAME" ] && env_args+=(-e "DB_USERNAME")
    [ -n "$DB_PASSWORD" ] && env_args+=(-e "DB_PASSWORD")
    [ -n "$DB_DATABASE" ] && env_args+=(-e "DB_DATABASE")
    [ -n "$BRAVE_API_KEY" ] && env_args+=(-e "BRAVE_API_KEY")

    log_info "Starting Claude Container..."
    log_info "  Container: $container_name"
    log_info "  CPU: $CPU_LIMIT cores"
    log_info "  Memory: $MEM_LIMIT"
    log_info "  Web access: ${CLAUDE_WEB_ACCESS:-off}"

    # Determine TTY flags - use -it only for interactive terminal
    local tty_flags=""
    if [ -t 0 ] && [ -t 1 ]; then
        tty_flags="-it"
    fi

    # Run container
    exec podman run $tty_flags $user_flags --rm \
        --name "$container_name" \
        --cpus="$CPU_LIMIT" \
        --memory="$MEM_LIMIT" \
        --cap-add NET_ADMIN \
        -v "$project_path:/workspace:Z" \
        "${auth_mounts[@]}" \
        "${env_args[@]}" \
        "$IMAGE_NAME" \
        "${cmd[@]}"
}

# Parse arguments
PROJECT_PATH=""
CLAUDE_ARGS=()
ACTION="run"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --build)
            ACTION="build"
            shift
            ;;
        --build-no-cache)
            ACTION="build-no-cache"
            shift
            ;;
        --pull)
            ACTION="pull"
            shift
            ;;
        --no-pull)
            AUTO_PULL="false"
            shift
            ;;
        --no-share-auth)
            SHARE_AUTH="false"
            shift
            ;;
        --new)
            NEW_SESSION="true"
            shift
            ;;
        --shell)
            ACTION="shell"
            shift
            ;;
        --status)
            ACTION="status"
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        --)
            shift
            CLAUDE_ARGS=("$@")
            break
            ;;
        -*)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
        *)
            if [ -z "$PROJECT_PATH" ]; then
                PROJECT_PATH="$1"
            else
                log_error "Unexpected argument: $1"
                show_help
                exit 1
            fi
            shift
            ;;
    esac
done

# Execute action
case "$ACTION" in
    build)
        build_image
        ;;
    build-no-cache)
        build_image --no-cache
        ;;
    pull)
        pull_image
        ;;
    status)
        show_status
        ;;
    shell)
        run_container "$PROJECT_PATH" /bin/bash
        ;;
    run)
        if [ ${#CLAUDE_ARGS[@]} -gt 0 ]; then
            # User provided args - don't add --resume (might conflict with --print etc)
            run_container "$PROJECT_PATH" claude --dangerously-skip-permissions "${CLAUDE_ARGS[@]}"
        else
            # Default: interactive with resume
            run_container "$PROJECT_PATH"
        fi
        ;;
esac
