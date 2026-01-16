#!/bin/bash
# Test suite for unique container naming
# Run: ./tests/test-container-naming.sh
#
# Tests the container naming scheme: claude_<project>_<HH-MM-SS>

set +e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PASSED=0
FAILED=0

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

echo "========================================"
echo "Container Naming Test Suite"
echo "========================================"
echo ""

# Source the generate_container_name function from claude-run.sh
# We'll test the function directly
source "$REPO_DIR/claude-run.sh" --source-only 2>/dev/null || true

# ========================================
# Test: generate_container_name function exists
# ========================================
log_test "generate_container_name function exists"
if declare -f generate_container_name >/dev/null 2>&1; then
    log_pass "generate_container_name function exists"
else
    log_fail "generate_container_name function exists"
    echo "  Hint: Function should be defined in claude-run.sh"
fi

# ========================================
# Test: Container name format (claude_<project>_<HH-MM-SS>)
# ========================================
log_test "Container name follows format claude_<project>_<HH-MM-SS>"
if declare -f generate_container_name >/dev/null 2>&1; then
    NAME=$(generate_container_name "/home/user/my-project")
    if [[ "$NAME" =~ ^claude_my-project_[0-9]{2}-[0-9]{2}-[0-9]{2}$ ]]; then
        log_pass "Container name follows format claude_<project>_<HH-MM-SS>"
        echo "  Generated: $NAME"
    else
        log_fail "Container name follows format claude_<project>_<HH-MM-SS>"
        echo "  Expected: claude_my-project_HH-MM-SS"
        echo "  Got: $NAME"
    fi
else
    log_fail "Container name follows format (function missing)"
fi

# ========================================
# Test: Project name extraction from path
# ========================================
log_test "Project name extracted correctly from path"
if declare -f generate_container_name >/dev/null 2>&1; then
    NAME=$(generate_container_name "/home/user/work/claude-container")
    if [[ "$NAME" == claude_claude-container_* ]]; then
        log_pass "Project name extracted correctly from path"
    else
        log_fail "Project name extracted correctly from path"
        echo "  Expected: claude_claude-container_*"
        echo "  Got: $NAME"
    fi
else
    log_fail "Project name extracted correctly from path (function missing)"
fi

# ========================================
# Test: Handles paths with spaces (sanitized)
# ========================================
log_test "Handles project names with spaces"
if declare -f generate_container_name >/dev/null 2>&1; then
    NAME=$(generate_container_name "/home/user/My Project")
    # Spaces should be replaced with underscores or removed
    if [[ ! "$NAME" =~ " " ]]; then
        log_pass "Handles project names with spaces"
        echo "  Generated: $NAME"
    else
        log_fail "Handles project names with spaces"
        echo "  Container name should not contain spaces"
        echo "  Got: $NAME"
    fi
else
    log_fail "Handles project names with spaces (function missing)"
fi

# ========================================
# Test: Handles special characters
# ========================================
log_test "Handles special characters in project names"
if declare -f generate_container_name >/dev/null 2>&1; then
    NAME=$(generate_container_name "/home/user/project@123")
    # Check the name is valid for podman (alphanumeric, dash, underscore, dot)
    if [[ "$NAME" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        log_pass "Handles special characters in project names"
        echo "  Generated: $NAME"
    else
        log_fail "Handles special characters in project names"
        echo "  Container name should only contain alphanumeric, dash, underscore, dot"
        echo "  Got: $NAME"
    fi
else
    log_fail "Handles special characters in project names (function missing)"
fi

# ========================================
# Test: Unique names on successive calls
# ========================================
log_test "Generates unique names on successive calls"
if declare -f generate_container_name >/dev/null 2>&1; then
    NAME1=$(generate_container_name "/home/user/project")
    sleep 1  # Ensure time changes
    NAME2=$(generate_container_name "/home/user/project")
    if [ "$NAME1" != "$NAME2" ]; then
        log_pass "Generates unique names on successive calls"
        echo "  Name 1: $NAME1"
        echo "  Name 2: $NAME2"
    else
        log_fail "Generates unique names on successive calls"
        echo "  Both calls returned: $NAME1"
    fi
else
    log_fail "Generates unique names on successive calls (function missing)"
fi

# ========================================
# Test: Current directory handling
# ========================================
log_test "Handles current directory (pwd)"
if declare -f generate_container_name >/dev/null 2>&1; then
    CURRENT_DIR=$(basename "$(pwd)")
    NAME=$(generate_container_name "$(pwd)")
    if [[ "$NAME" == claude_${CURRENT_DIR}_* ]] || [[ "$NAME" =~ ^claude_.*_[0-9]{2}-[0-9]{2}-[0-9]{2}$ ]]; then
        log_pass "Handles current directory (pwd)"
        echo "  Generated: $NAME"
    else
        log_fail "Handles current directory (pwd)"
        echo "  Expected: claude_${CURRENT_DIR}_HH-MM-SS"
        echo "  Got: $NAME"
    fi
else
    log_fail "Handles current directory (function missing)"
fi

# ========================================
# Test: Long project names are truncated
# ========================================
log_test "Truncates long project names"
if declare -f generate_container_name >/dev/null 2>&1; then
    LONG_NAME="this-is-a-very-long-project-name-that-exceeds-reasonable-limits"
    NAME=$(generate_container_name "/home/user/$LONG_NAME")
    # Container names should be reasonable length (< 64 chars typical limit)
    if [ ${#NAME} -lt 64 ]; then
        log_pass "Truncates long project names"
        echo "  Generated: $NAME (${#NAME} chars)"
    else
        log_fail "Truncates long project names"
        echo "  Name too long: ${#NAME} chars"
        echo "  Got: $NAME"
    fi
else
    log_fail "Truncates long project names (function missing)"
fi

echo ""
echo "========================================"
echo "TEST SUMMARY"
echo "========================================"
echo -e "Passed:  ${GREEN}$PASSED${NC}"
echo -e "Failed:  ${RED}$FAILED${NC}"
echo ""

if [ $FAILED -gt 0 ]; then
    echo -e "${RED}TESTS FAILED${NC}"
    exit 1
else
    echo -e "${GREEN}ALL TESTS PASSED${NC}"
    exit 0
fi
