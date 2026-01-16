#!/bin/bash
# Database Integration Test Suite for Claude Container
# Run: ./tests/integration/test-db-integration.sh
#
# Prerequisites:
#   - MSSQL Server accessible at DB_SERVER
#   - .env.test configured with credentials
#   - Python with pyodbc installed
#
# This can run either on the host or inside the container.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEST_DATA_DIR="$SCRIPT_DIR/test_data"
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

cleanup() {
    log_info "Cleaning up..."
    rm -rf "$OUTPUT_DIR"

    # Drop test schema if it exists
    if [ -n "$DB_SERVER" ] && [ -n "$DB_DATABASE" ]; then
        python3 "$SCRIPT_DIR/db_utils.py" \
            --server "$DB_SERVER" \
            --database "$DB_DATABASE" \
            --user "$DB_USERNAME" \
            --password "$DB_PASSWORD" \
            drop-schema --schema claude_container 2>/dev/null || true
    fi
}

# Load environment
load_env() {
    if [ -f "$PROJECT_ROOT/.env.test" ]; then
        log_info "Loading .env.test"
        source "$PROJECT_ROOT/.env.test"
    elif [ -f "$SCRIPT_DIR/.env.test" ]; then
        log_info "Loading integration/.env.test"
        source "$SCRIPT_DIR/.env.test"
    else
        echo -e "${RED}ERROR: No .env.test found${NC}"
        echo "Copy .env.test.template to .env.test and configure credentials"
        exit 1
    fi

    # Validate required variables
    if [ -z "$DB_SERVER" ] || [ -z "$DB_DATABASE" ] || [ -z "$DB_USERNAME" ] || [ -z "$DB_PASSWORD" ]; then
        echo -e "${RED}ERROR: Missing required environment variables${NC}"
        echo "Required: DB_SERVER, DB_DATABASE, DB_USERNAME, DB_PASSWORD"
        exit 1
    fi

    log_info "Database: $DB_SERVER / $DB_DATABASE"
}

# Create output directory
setup() {
    mkdir -p "$OUTPUT_DIR"
}

# ========================================
# TEST 1: Connection Test
# ========================================
test_connection() {
    log_test "Database connection"

    if python3 "$SCRIPT_DIR/db_utils.py" \
        --server "$DB_SERVER" \
        --database "$DB_DATABASE" \
        --user "$DB_USERNAME" \
        --password "$DB_PASSWORD" \
        test; then
        log_pass "Database connection"
        return 0
    else
        log_fail "Database connection"
        return 1
    fi
}

# ========================================
# TEST 2: Query sys tables
# ========================================
test_sys_query() {
    log_test "Query sys.databases"

    local result
    result=$(python3 -c "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from db_utils import get_connection, execute_query

conn = get_connection('$DB_SERVER', '$DB_DATABASE', '$DB_USERNAME', '$DB_PASSWORD')
rows = execute_query(conn, 'SELECT name FROM sys.databases WHERE name = ?', ('$DB_DATABASE',))
conn.close()

if rows and len(rows) > 0:
    print('OK')
else:
    print('FAIL')
" 2>&1)

    if [ "$result" = "OK" ]; then
        log_pass "Query sys.databases"
        return 0
    else
        log_fail "Query sys.databases: $result"
        return 1
    fi
}

# ========================================
# TEST 3: Create schema
# ========================================
test_create_schema() {
    log_test "Create schema 'claude_container'"

    local result
    result=$(python3 -c "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from db_utils import get_connection, create_schema, schema_exists

conn = get_connection('$DB_SERVER', '$DB_DATABASE', '$DB_USERNAME', '$DB_PASSWORD')
create_schema(conn, 'claude_container')
exists = schema_exists(conn, 'claude_container')
conn.close()

print('OK' if exists else 'FAIL')
" 2>&1)

    if echo "$result" | grep -q "OK"; then
        log_pass "Create schema 'claude_container'"
        return 0
    else
        log_fail "Create schema: $result"
        return 1
    fi
}

# ========================================
# TEST 4: Import CSV to table
# ========================================
test_import_csv() {
    log_test "Import CSV to table"

    local result
    result=$(python3 -c "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from db_utils import get_connection, import_csv, table_exists

conn = get_connection('$DB_SERVER', '$DB_DATABASE', '$DB_USERNAME', '$DB_PASSWORD')
rows = import_csv(conn, '$TEST_DATA_DIR/sample_products.csv', 'claude_container', 'products', create_table=True)
exists = table_exists(conn, 'claude_container', 'products')
conn.close()

if exists and rows == 10:
    print('OK')
else:
    print(f'FAIL: exists={exists}, rows={rows}')
" 2>&1)

    if echo "$result" | grep -q "OK"; then
        log_pass "Import CSV to table (10 rows)"
        return 0
    else
        log_fail "Import CSV: $result"
        return 1
    fi
}

# ========================================
# TEST 5: Query imported data
# ========================================
test_query_imported() {
    log_test "Query imported data"

    local result
    result=$(python3 -c "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from db_utils import get_connection, execute_query

conn = get_connection('$DB_SERVER', '$DB_DATABASE', '$DB_USERNAME', '$DB_PASSWORD')
rows = execute_query(conn, '''
    SELECT COUNT(*) as cnt, SUM(quantity) as total_qty
    FROM [claude_container].[products]
''')
conn.close()

if rows and rows[0][0] == 10 and rows[0][1] == 1665:
    print('OK')
else:
    print(f'FAIL: {rows}')
" 2>&1)

    if echo "$result" | grep -q "OK"; then
        log_pass "Query imported data"
        return 0
    else
        log_fail "Query imported: $result"
        return 1
    fi
}

# ========================================
# TEST 6: Export table to CSV
# ========================================
test_export_csv() {
    log_test "Export table to CSV"

    local result
    result=$(python3 -c "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from db_utils import get_connection, export_csv

conn = get_connection('$DB_SERVER', '$DB_DATABASE', '$DB_USERNAME', '$DB_PASSWORD')
rows = export_csv(conn, 'claude_container', 'products', '$OUTPUT_DIR/exported_products.csv')
conn.close()

if rows == 10:
    print('OK')
else:
    print(f'FAIL: rows={rows}')
" 2>&1)

    if echo "$result" | grep -q "OK"; then
        log_pass "Export table to CSV (10 rows)"
        return 0
    else
        log_fail "Export CSV: $result"
        return 1
    fi
}

# ========================================
# TEST 7: Compare original vs exported
# ========================================
test_compare_csv() {
    log_test "Compare original vs exported CSV"

    if python3 "$SCRIPT_DIR/db_utils.py" \
        --server "$DB_SERVER" \
        --database "$DB_DATABASE" \
        --user "$DB_USERNAME" \
        --password "$DB_PASSWORD" \
        compare \
        --file1 "$TEST_DATA_DIR/sample_products.csv" \
        --file2 "$OUTPUT_DIR/exported_products.csv" 2>&1 | grep -q "match"; then
        log_pass "Compare original vs exported CSV"
        return 0
    else
        log_fail "CSV comparison failed - files differ"
        # Show differences
        python3 "$SCRIPT_DIR/db_utils.py" \
            --server "$DB_SERVER" \
            --database "$DB_DATABASE" \
            --user "$DB_USERNAME" \
            --password "$DB_PASSWORD" \
            compare \
            --file1 "$TEST_DATA_DIR/sample_products.csv" \
            --file2 "$OUTPUT_DIR/exported_products.csv" 2>&1 | head -10
        return 1
    fi
}

# ========================================
# TEST 8: Import second table
# ========================================
test_import_second_table() {
    log_test "Import second CSV (customers)"

    local result
    result=$(python3 -c "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from db_utils import get_connection, import_csv, table_exists

conn = get_connection('$DB_SERVER', '$DB_DATABASE', '$DB_USERNAME', '$DB_PASSWORD')
rows = import_csv(conn, '$TEST_DATA_DIR/sample_customers.csv', 'claude_container', 'customers', create_table=True)
exists = table_exists(conn, 'claude_container', 'customers')
conn.close()

if exists and rows == 5:
    print('OK')
else:
    print(f'FAIL: exists={exists}, rows={rows}')
" 2>&1)

    if echo "$result" | grep -q "OK"; then
        log_pass "Import second CSV (5 rows)"
        return 0
    else
        log_fail "Import second CSV: $result"
        return 1
    fi
}

# ========================================
# TEST 9: Join query across tables
# ========================================
test_join_query() {
    log_test "Cross-table query"

    local result
    result=$(python3 -c "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from db_utils import get_connection, execute_query

conn = get_connection('$DB_SERVER', '$DB_DATABASE', '$DB_USERNAME', '$DB_PASSWORD')
# Simple validation that both tables exist and can be referenced
rows = execute_query(conn, '''
    SELECT
        (SELECT COUNT(*) FROM [claude_container].[products]) as product_count,
        (SELECT COUNT(*) FROM [claude_container].[customers]) as customer_count
''')
conn.close()

if rows and rows[0][0] == 10 and rows[0][1] == 5:
    print('OK')
else:
    print(f'FAIL: {rows}')
" 2>&1)

    if echo "$result" | grep -q "OK"; then
        log_pass "Cross-table query"
        return 0
    else
        log_fail "Cross-table query: $result"
        return 1
    fi
}

# ========================================
# TEST 10: Cleanup (drop schema)
# ========================================
test_cleanup_schema() {
    log_test "Drop schema 'claude_container'"

    local result
    result=$(python3 -c "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from db_utils import get_connection, drop_schema, schema_exists

conn = get_connection('$DB_SERVER', '$DB_DATABASE', '$DB_USERNAME', '$DB_PASSWORD')
drop_schema(conn, 'claude_container', cascade=True)
exists = schema_exists(conn, 'claude_container')
conn.close()

print('OK' if not exists else 'FAIL')
" 2>&1)

    if echo "$result" | grep -q "OK"; then
        log_pass "Drop schema 'claude_container'"
        return 0
    else
        log_fail "Drop schema: $result"
        return 1
    fi
}

# ========================================
# MAIN
# ========================================
main() {
    echo "========================================"
    echo "Claude Container DB Integration Tests"
    echo "========================================"
    echo ""

    load_env
    setup

    # Set trap for cleanup on exit
    trap cleanup EXIT

    echo ""
    echo -e "${BLUE}=== CONNECTION TESTS ===${NC}"
    test_connection || true
    test_sys_query || true

    echo ""
    echo -e "${BLUE}=== SCHEMA TESTS ===${NC}"
    test_create_schema || true

    echo ""
    echo -e "${BLUE}=== CSV IMPORT/EXPORT TESTS ===${NC}"
    test_import_csv || true
    test_query_imported || true
    test_export_csv || true
    test_compare_csv || true

    echo ""
    echo -e "${BLUE}=== MULTI-TABLE TESTS ===${NC}"
    test_import_second_table || true
    test_join_query || true

    echo ""
    echo -e "${BLUE}=== CLEANUP TESTS ===${NC}"
    test_cleanup_schema || true

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
