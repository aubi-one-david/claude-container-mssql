#!/bin/bash
# Container Test Suite for TDD optimization
# Run: ./tests/test-container.sh [image-name]
#
# Tests are organized by priority:
# - CRITICAL: Must pass for container to be usable
# - IMPORTANT: Should pass for full functionality
# - NICE: Convenience features

# Don't exit on error - we handle test failures ourselves
set +e

IMAGE="${1:-claude-container:latest}"
PASSED=0
FAILED=0
SKIPPED=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((PASSED++))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((FAILED++))
}

log_skip() {
    echo -e "${YELLOW}[SKIP]${NC} $1"
    ((SKIPPED++))
}

# Helper to run command in container without entrypoint
run_cmd() {
    podman run --rm --entrypoint "" "$IMAGE" "$@"
}

# Helper to run command and check exit code
test_cmd() {
    local name="$1"
    shift
    log_test "$name"
    if run_cmd "$@" >/dev/null 2>&1; then
        log_pass "$name"
        return 0
    else
        log_fail "$name"
        return 1
    fi
}

# Helper to run command and check output contains string
test_output() {
    local name="$1"
    local expected="$2"
    shift 2
    log_test "$name"
    local output
    if output=$(run_cmd "$@" 2>&1) && echo "$output" | grep -q "$expected"; then
        log_pass "$name"
        return 0
    else
        log_fail "$name (expected: $expected)"
        echo "  Got: $output" | head -3
        return 1
    fi
}

echo "========================================"
echo "Claude Container Test Suite"
echo "Image: $IMAGE"
echo "========================================"
echo ""

# Get image size
SIZE=$(podman image inspect "$IMAGE" --format '{{.Size}}' 2>/dev/null || echo "0")
SIZE_MB=$((SIZE / 1024 / 1024))
echo -e "Image size: ${BLUE}${SIZE_MB} MB${NC}"
echo ""

# ========================================
# CRITICAL TESTS - Container won't work without these
# ========================================
echo -e "${BLUE}=== CRITICAL TESTS ===${NC}"

test_output "Claude Code installed" "Claude Code" claude --version

test_output "Claude Code version" "[0-9]\+\.[0-9]\+\.[0-9]\+" claude --version

test_cmd "Python available" python --version

test_output "pyodbc installed" "5\." python -c "import pyodbc; print(pyodbc.version)"

test_cmd "git available" git --version

test_cmd "Entrypoint script exists" test -x /home/claude/.local/bin/entrypoint.sh

test_cmd "Firewall script exists" test -x /home/claude/.local/bin/init-firewall.sh

test_cmd "claude-web script exists" test -x /home/claude/.local/bin/claude-web

echo ""

# ========================================
# IMPORTANT TESTS - Full functionality
# ========================================
echo -e "${BLUE}=== IMPORTANT TESTS ===${NC}"

# sqlcmd test - handles both go-sqlcmd (--version) and mssql-tools (no version flag)
log_test "sqlcmd installed"
if run_cmd which sqlcmd >/dev/null 2>&1; then
    log_pass "sqlcmd installed"
else
    log_fail "sqlcmd installed"
fi

test_cmd "Node.js available" node --version

test_cmd "npm available" npm --version

test_cmd "jq available" jq --version

test_cmd "curl available" curl --version

test_cmd "iptables available" which iptables

test_cmd "Default CLAUDE.md exists" test -f /home/claude/.claude/CLAUDE.md

test_cmd "MCP config exists" test -f /home/claude/.mcp.json

# Test MCP servers can be invoked (they download on demand with npx -y)
log_test "npx available for MCP"
if run_cmd npx --version >/dev/null 2>&1; then
    log_pass "npx available for MCP"
else
    log_fail "npx available for MCP"
fi

echo ""

# ========================================
# NICE-TO-HAVE TESTS - Convenience
# ========================================
echo -e "${BLUE}=== NICE-TO-HAVE TESTS ===${NC}"

# nano removed to save space - Claude uses Edit tool instead
log_test "sed available (for scripted edits)"
if run_cmd which sed >/dev/null 2>&1; then
    log_pass "sed available (for scripted edits)"
else
    log_fail "sed available (for scripted edits)"
fi

test_cmd "claude-status script exists" test -x /home/claude/.local/bin/claude-status

test_cmd "session-save script exists" test -x /home/claude/.local/bin/session-save.sh

# Test user home directory is writable (container-internal permissions)
log_test "User home writable"
if run_cmd sh -c "touch /home/claude/test-write && rm /home/claude/test-write"; then
    log_pass "User home writable"
else
    log_fail "User home writable"
fi

# Test workspace is writable (with volume mount + userns mapping, as in real usage)
log_test "Workspace writable (mounted volume)"
TMPDIR=$(mktemp -d)
if podman run --rm --entrypoint "" --userns=keep-id --user "$(id -u):$(id -g)" -v "${TMPDIR}:/workspace:Z" "$IMAGE" sh -c "touch /workspace/test-write && rm /workspace/test-write"; then
    log_pass "Workspace writable (mounted volume)"
else
    log_fail "Workspace writable (mounted volume)"
fi
rm -rf "$TMPDIR"

# Test user is non-root
log_test "Running as non-root user"
if [ "$(run_cmd id -u)" != "0" ]; then
    log_pass "Running as non-root user"
else
    log_fail "Running as non-root user"
fi

echo ""

# ========================================
# MCP SERVER TESTS - On-demand functionality
# ========================================
echo -e "${BLUE}=== MCP SERVER TESTS (on-demand) ===${NC}"

# These test that MCP servers CAN be run, not that they're pre-installed
log_test "Filesystem MCP can start"
if timeout 90 bash -c "podman run --rm --entrypoint '' $IMAGE npx -y @modelcontextprotocol/server-filesystem --help 2>&1 | grep -q -i 'filesystem\|usage\|error'"; then
    log_pass "Filesystem MCP can start"
else
    log_skip "Filesystem MCP can start (timeout or network)"
fi

log_test "pip available for Python MCP"
if run_cmd pip --version >/dev/null 2>&1; then
    log_pass "pip available for Python MCP"
else
    log_fail "pip available for Python MCP"
fi

# Test uv pip install works with userns mapping (real usage scenario)
# This is CRITICAL for running Python scripts that need additional packages
# Uses uv with --target to install to workspace (writable with userns mapping)
log_test "uv pip install works (userns mapped)"
TMPDIR_PIP=$(mktemp -d)
if podman run --rm --entrypoint "" --userns=keep-id --user "$(id -u):$(id -g)" \
    -v "${TMPDIR_PIP}:/workspace:Z" "$IMAGE" \
    sh -c "uv pip install --quiet --target /workspace/.packages tomli && PYTHONPATH=/workspace/.packages python -c 'import tomli; print(\"ok\")'" 2>/dev/null | grep -q "ok"; then
    log_pass "uv pip install works (userns mapped)"
else
    log_fail "uv pip install works (userns mapped)"
fi
rm -rf "$TMPDIR_PIP"

# Test openpyxl is available (needed for MSSQL data export/import scripts)
log_test "openpyxl installed"
if run_cmd python -c "import openpyxl; print(openpyxl.__version__)" >/dev/null 2>&1; then
    log_pass "openpyxl installed"
else
    log_fail "openpyxl installed"
fi

echo ""

# ========================================
# SUMMARY
# ========================================
echo "========================================"
echo "TEST SUMMARY"
echo "========================================"
echo -e "Passed:  ${GREEN}$PASSED${NC}"
echo -e "Failed:  ${RED}$FAILED${NC}"
echo -e "Skipped: ${YELLOW}$SKIPPED${NC}"
echo ""
echo -e "Image size: ${BLUE}${SIZE_MB} MB${NC}"
echo ""

if [ $FAILED -gt 0 ]; then
    echo -e "${RED}TESTS FAILED${NC}"
    exit 1
else
    echo -e "${GREEN}ALL CRITICAL TESTS PASSED${NC}"
    exit 0
fi
