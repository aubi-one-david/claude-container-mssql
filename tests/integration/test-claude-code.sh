#!/bin/bash
# Claude Code Integration Test Suite for Claude Container
# Run: ./tests/integration/test-claude-code.sh
#
# Prerequisites:
#   - Claude Code installed
#   - Either ANTHROPIC_API_KEY set OR ~/.claude mounted with OAuth credentials
#
# This tests Claude Code functionality: context, hooks, API, sessions

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEST_WORKSPACE="$SCRIPT_DIR/test_workspace"
OUTPUT_DIR="$SCRIPT_DIR/output"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASSED=0
FAILED=0
SKIPPED=0

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

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

# Load environment
load_env() {
    if [ -f "$PROJECT_ROOT/.env.test" ]; then
        source "$PROJECT_ROOT/.env.test"
    fi

    # Check for API authentication
    if [ -z "$ANTHROPIC_API_KEY" ]; then
        echo -e "${YELLOW}NOTE: No ANTHROPIC_API_KEY set${NC}"
        echo "  API tests require an API key for non-interactive use."
        echo "  Add to your parent .env file:"
        echo "    ANTHROPIC_API_KEY=sk-ant-api03-..."
        echo ""
        echo "  OAuth credentials (interactive only) cannot be used in containers."
        HAS_API_KEY=0
    else
        echo -e "${GREEN}API key configured${NC}"
        HAS_API_KEY=1
    fi
}

# Setup test workspace with hooks, context, etc.
setup_workspace() {
    log_info "Setting up test workspace..."
    rm -rf "$TEST_WORKSPACE"
    mkdir -p "$TEST_WORKSPACE/.claude/hooks"
    mkdir -p "$TEST_WORKSPACE/.claude/agents"
    mkdir -p "$TEST_WORKSPACE/.claude-sessions"
    mkdir -p "$OUTPUT_DIR"

    # Create test CLAUDE.md
    cat > "$TEST_WORKSPACE/CLAUDE.md" << 'EOF'
# Test Project Context

This is a test workspace for Claude Container integration tests.

## Test Variables
- TEST_VAR_1: apple
- TEST_VAR_2: banana
- TEST_VAR_3: cherry

## Instructions
When asked about test variables, respond with the values defined above.
EOF

    # Create test hook
    cat > "$TEST_WORKSPACE/.claude/hooks/test-hook.sh" << 'EOF'
#!/bin/bash
# Test hook for integration testing
echo "TEST_HOOK_EXECUTED"
exit 0
EOF
    chmod +x "$TEST_WORKSPACE/.claude/hooks/test-hook.sh"

    # Create test agent
    cat > "$TEST_WORKSPACE/.claude/agents/test-agent.md" << 'EOF'
# Test Agent

A simple test agent for verification.

## Capabilities
- Respond to test queries
- Return structured test data
EOF

    # Create settings.json with hook config
    cat > "$TEST_WORKSPACE/.claude/settings.json" << 'EOF'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [".claude/hooks/test-hook.sh"]
      }
    ]
  }
}
EOF

    log_info "Test workspace created at $TEST_WORKSPACE"
}

cleanup() {
    log_info "Cleaning up..."
    rm -rf "$TEST_WORKSPACE"
    rm -rf "$OUTPUT_DIR"
}

# ========================================
# TEST 1: Claude Code version
# ========================================
test_claude_version() {
    log_test "Claude Code version check"

    local version
    if version=$(claude --version 2>&1); then
        if echo "$version" | grep -qE "[0-9]+\.[0-9]+\.[0-9]+"; then
            log_pass "Claude Code version: $(echo "$version" | grep -oE "[0-9]+\.[0-9]+\.[0-9]+")"
            return 0
        fi
    fi
    log_fail "Claude Code version check"
    return 1
}

# ========================================
# TEST 2: Claude Code help
# ========================================
test_claude_help() {
    log_test "Claude Code help"

    if claude --help 2>&1 | grep -q "dangerously-skip-permissions"; then
        log_pass "Claude Code help (--dangerously-skip-permissions available)"
        return 0
    else
        log_fail "Claude Code help"
        return 1
    fi
}

# ========================================
# TEST 3: API connectivity (non-interactive)
# ========================================
test_api_connectivity() {
    log_test "API connectivity"

    # Check if we have API key (OAuth doesn't work non-interactively)
    if [ "${HAS_API_KEY:-0}" != "1" ]; then
        log_skip "API connectivity (no API key)"
        return 0
    fi

    # Use claude with a simple prompt in print mode
    local result
    if result=$(timeout 30 claude --print "Reply with exactly: API_TEST_OK" 2>&1); then
        if echo "$result" | grep -q "API_TEST_OK"; then
            log_pass "API connectivity"
            return 0
        fi
    fi

    # Check for auth errors vs other errors
    if echo "$result" | grep -qi "unauthorized\|invalid.*key\|authentication"; then
        log_fail "API connectivity (authentication error)"
    else
        log_fail "API connectivity: $result"
    fi
    return 1
}

# ========================================
# TEST 4: Context loading (CLAUDE.md)
# ========================================
test_context_loading() {
    log_test "Context loading (CLAUDE.md)"

    # Check if we have authentication
    if [ "${HAS_API_KEY:-0}" != "1" ]; then
        log_skip "Context loading (no credentials)"
        return 0
    fi

    cd "$TEST_WORKSPACE"

    # Ask Claude about the test variables defined in CLAUDE.md
    local result
    if result=$(timeout 60 claude --print "What is the value of TEST_VAR_2 according to the project context?" 2>&1); then
        if echo "$result" | grep -qi "banana"; then
            log_pass "Context loading (read TEST_VAR_2=banana from CLAUDE.md)"
            return 0
        fi
    fi

    log_fail "Context loading: expected 'banana' in response"
    echo "  Got: $(echo "$result" | head -3)"
    return 1
}

# ========================================
# TEST 5: Hooks visibility
# ========================================
test_hooks_visibility() {
    log_test "Hooks configuration visible"

    cd "$TEST_WORKSPACE"

    # Check that settings.json with hooks exists and is valid
    if [ -f ".claude/settings.json" ]; then
        if jq -e '.hooks' .claude/settings.json > /dev/null 2>&1; then
            local hook_count
            hook_count=$(jq '.hooks | length' .claude/settings.json)
            log_pass "Hooks configuration visible ($hook_count hook types configured)"
            return 0
        fi
    fi

    log_fail "Hooks configuration not found or invalid"
    return 1
}

# ========================================
# TEST 6: Agents directory
# ========================================
test_agents_directory() {
    log_test "Agents directory"

    cd "$TEST_WORKSPACE"

    if [ -d ".claude/agents" ] && [ -f ".claude/agents/test-agent.md" ]; then
        local agent_count
        agent_count=$(ls -1 .claude/agents/*.md 2>/dev/null | wc -l)
        log_pass "Agents directory ($agent_count agents found)"
        return 0
    fi

    log_fail "Agents directory not found or empty"
    return 1
}

# ========================================
# TEST 7: Session directory creation
# ========================================
test_session_directory() {
    log_test "Session directory"

    cd "$TEST_WORKSPACE"

    if [ -d ".claude-sessions" ]; then
        log_pass "Session directory exists"
        return 0
    fi

    log_fail "Session directory not found"
    return 1
}

# ========================================
# TEST 8: Print mode (non-interactive output)
# ========================================
test_print_mode() {
    log_test "Print mode (--print)"

    if [ "${HAS_API_KEY:-0}" != "1" ]; then
        log_skip "Print mode (no credentials)"
        return 0
    fi

    local result
    if result=$(timeout 30 claude --print "What is 2+2? Reply with just the number." 2>&1); then
        if echo "$result" | grep -q "4"; then
            log_pass "Print mode works"
            return 0
        fi
    fi

    log_fail "Print mode: unexpected response"
    return 1
}

# ========================================
# TEST 9: Output format JSON
# ========================================
test_output_json() {
    log_test "Output format JSON"

    if [ "${HAS_API_KEY:-0}" != "1" ]; then
        log_skip "Output JSON (no credentials)"
        return 0
    fi

    local result
    if result=$(timeout 30 claude --print --output-format json "Reply with: hello" 2>&1); then
        if echo "$result" | jq -e '.result' > /dev/null 2>&1; then
            log_pass "Output format JSON"
            return 0
        fi
    fi

    log_fail "Output format JSON: invalid JSON response"
    return 1
}

# ========================================
# TEST 10: Session creation and resume
# ========================================
test_session_resume() {
    log_test "Session creation and resume"

    if [ "${HAS_API_KEY:-0}" != "1" ]; then
        log_skip "Session resume (no credentials)"
        return 0
    fi

    cd "$TEST_WORKSPACE"

    # Create a session with a unique marker
    local marker="UNIQUE_MARKER_$(date +%s)"
    local session_result

    # Start a session and ask it to remember something
    session_result=$(timeout 60 claude --print "Remember this code: $marker. Reply with 'STORED'" 2>&1)

    if ! echo "$session_result" | grep -qi "STORED"; then
        log_fail "Session creation: failed to store marker"
        return 1
    fi

    # Try to resume (this tests --resume flag exists)
    if claude --help 2>&1 | grep -q "\-\-resume"; then
        log_pass "Session resume (--resume flag available)"
        return 0
    fi

    log_fail "Session resume: --resume flag not found"
    return 1
}

# ========================================
# TEST 11: Model selection
# ========================================
test_model_selection() {
    log_test "Model selection"

    if claude --help 2>&1 | grep -qE "\-\-model|\-m"; then
        log_pass "Model selection (--model flag available)"
        return 0
    fi

    log_fail "Model selection: --model flag not found"
    return 1
}

# ========================================
# TEST 12: MCP config location
# ========================================
test_mcp_config() {
    log_test "MCP configuration"

    # Check for MCP config in standard locations
    local mcp_found=0

    if [ -f "$HOME/.mcp.json" ]; then
        mcp_found=1
        log_info "Found ~/.mcp.json"
    fi

    if [ -f "$TEST_WORKSPACE/.mcp.json" ]; then
        mcp_found=1
        log_info "Found workspace .mcp.json"
    fi

    if [ $mcp_found -eq 1 ]; then
        log_pass "MCP configuration found"
        return 0
    fi

    # Not a failure if not configured, just informational
    log_pass "MCP configuration (none configured - optional)"
    return 0
}

# ========================================
# MAIN
# ========================================
main() {
    echo "========================================"
    echo "Claude Code Integration Tests"
    echo "========================================"
    echo ""

    load_env
    setup_workspace

    # Set trap for cleanup on exit
    trap cleanup EXIT

    echo ""
    echo -e "${BLUE}=== BASIC TESTS ===${NC}"
    test_claude_version || true
    test_claude_help || true
    test_model_selection || true

    echo ""
    echo -e "${BLUE}=== CONFIGURATION TESTS ===${NC}"
    test_hooks_visibility || true
    test_agents_directory || true
    test_session_directory || true
    test_mcp_config || true

    echo ""
    echo -e "${BLUE}=== API TESTS ===${NC}"
    test_api_connectivity || true
    test_print_mode || true
    test_output_json || true

    echo ""
    echo -e "${BLUE}=== CONTEXT & SESSION TESTS ===${NC}"
    test_context_loading || true
    test_session_resume || true

    # Summary
    echo ""
    echo "========================================"
    echo "TEST SUMMARY"
    echo "========================================"
    echo -e "Passed:  ${GREEN}$PASSED${NC}"
    echo -e "Failed:  ${RED}$FAILED${NC}"
    echo -e "Skipped: ${YELLOW}$SKIPPED${NC}"
    echo ""

    if [ $FAILED -gt 0 ]; then
        echo -e "${RED}SOME TESTS FAILED${NC}"
        exit 1
    else
        echo -e "${GREEN}ALL TESTS PASSED${NC}"
        exit 0
    fi
}

main "$@"
