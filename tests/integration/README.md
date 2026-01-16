# Database Integration Tests

Integration tests for Claude Container that verify MSSQL connectivity and data operations.

## Prerequisites

1. MSSQL Server accessible (e.g., `mssql.local`)
2. Python 3 with pyodbc installed
3. ODBC Driver 18 for SQL Server

## Setup

1. Copy the environment template:
   ```bash
   cp .env.test.template .env.test
   ```

2. Edit `.env.test` with your database credentials:
   ```bash
   DB_SERVER="mssql.local"
   DB_DATABASE="claude_container_test"
   DB_USERNAME="SA"
   DB_PASSWORD="YourPassword"
   ```

   For security, the template can source credentials from a parent directory:
   ```bash
   source ../.env
   ```

## Running Tests

### From Host
```bash
./tests/integration/test-db-integration.sh
```

### From Container
```bash
podman run --rm \
    -v $(pwd)/tests:/workspace/tests:ro \
    -v $(pwd)/.env.test:/workspace/.env.test:ro \
    --entrypoint "" \
    claude-container:latest \
    /workspace/tests/integration/test-db-integration.sh
```

## Test Scenarios

1. **Connection Test** - Verify database connectivity
2. **Sys Query** - Query sys.databases to verify permissions
3. **Create Schema** - Create `claude_container` test schema
4. **Import CSV** - Load `sample_products.csv` into a table
5. **Query Data** - Verify imported data integrity
6. **Export CSV** - Export table back to CSV
7. **Compare CSV** - Verify export matches original
8. **Multi-table** - Import second table, run cross-table queries
9. **Cleanup** - Drop test schema and all objects

## Files

- `test-db-integration.sh` - Main test runner
- `db_utils.py` - Python utilities for DB operations
- `test_data/` - Sample CSV files for testing
  - `sample_products.csv` - 10 product records
  - `sample_customers.csv` - 5 customer records

## Using db_utils.py Directly

```bash
# Test connection
python3 db_utils.py --server mssql.local --database testdb --user SA --password Pass test

# Import CSV
python3 db_utils.py --server mssql.local --database testdb --user SA --password Pass \
    import --csv data.csv --schema dbo --table mytable

# Export CSV
python3 db_utils.py --server mssql.local --database testdb --user SA --password Pass \
    export --csv output.csv --schema dbo --table mytable

# Compare CSVs
python3 db_utils.py --server mssql.local --database testdb --user SA --password Pass \
    compare --file1 original.csv --file2 exported.csv

# Drop schema
python3 db_utils.py --server mssql.local --database testdb --user SA --password Pass \
    drop-schema --schema myschema
```
