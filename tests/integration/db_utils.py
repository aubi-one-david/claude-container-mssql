#!/usr/bin/env python3
"""
Database utilities for Claude Container integration tests.
Simplified CSV import/export and DB operations using pyodbc.
"""

import csv
import os
import sys
import argparse
from pathlib import Path
from typing import Optional, List, Dict, Any


def get_connection(server: str, database: str, username: str, password: str,
                   driver: str = "ODBC Driver 18 for SQL Server",
                   trust_cert: bool = True):
    """Create a pyodbc connection to SQL Server."""
    import pyodbc

    conn_str = (
        f"DRIVER={{{driver}}};"
        f"SERVER={server};"
        f"DATABASE={database};"
        f"UID={username};"
        f"PWD={password};"
    )
    if trust_cert:
        conn_str += "TrustServerCertificate=yes;"

    return pyodbc.connect(conn_str, autocommit=False)


def test_connection(server: str, database: str, username: str, password: str) -> bool:
    """Test database connection and return True if successful."""
    try:
        conn = get_connection(server, database, username, password)
        cursor = conn.cursor()
        cursor.execute("SELECT @@VERSION")
        version = cursor.fetchone()[0]
        print(f"Connected successfully!")
        print(f"SQL Server version: {version.split()[0]} {version.split()[1]} {version.split()[2]}")
        conn.close()
        return True
    except Exception as e:
        print(f"Connection failed: {e}")
        return False


def execute_query(conn, query: str, params: tuple = None) -> List[tuple]:
    """Execute a query and return results."""
    cursor = conn.cursor()
    if params:
        cursor.execute(query, params)
    else:
        cursor.execute(query)

    if cursor.description:
        return cursor.fetchall()
    return []


def execute_sql(conn, sql: str) -> int:
    """Execute SQL statement(s) and return rows affected."""
    cursor = conn.cursor()
    cursor.execute(sql)
    return cursor.rowcount


def schema_exists(conn, schema_name: str) -> bool:
    """Check if a schema exists."""
    cursor = conn.cursor()
    cursor.execute(
        "SELECT COUNT(*) FROM sys.schemas WHERE name = ?",
        (schema_name,)
    )
    return cursor.fetchone()[0] > 0


def table_exists(conn, schema_name: str, table_name: str) -> bool:
    """Check if a table exists."""
    cursor = conn.cursor()
    cursor.execute(
        """SELECT COUNT(*) FROM sys.tables t
           JOIN sys.schemas s ON t.schema_id = s.schema_id
           WHERE s.name = ? AND t.name = ?""",
        (schema_name, table_name)
    )
    return cursor.fetchone()[0] > 0


def create_schema(conn, schema_name: str) -> bool:
    """Create a schema if it doesn't exist."""
    if schema_exists(conn, schema_name):
        print(f"Schema '{schema_name}' already exists")
        return True

    cursor = conn.cursor()
    cursor.execute(f"CREATE SCHEMA [{schema_name}]")
    conn.commit()
    print(f"Created schema '{schema_name}'")
    return True


def drop_schema(conn, schema_name: str, cascade: bool = True) -> bool:
    """Drop a schema and optionally all objects in it."""
    if not schema_exists(conn, schema_name):
        print(f"Schema '{schema_name}' does not exist")
        return True

    cursor = conn.cursor()

    if cascade:
        # Drop all tables in schema first
        cursor.execute(
            """SELECT t.name FROM sys.tables t
               JOIN sys.schemas s ON t.schema_id = s.schema_id
               WHERE s.name = ?""",
            (schema_name,)
        )
        tables = [row[0] for row in cursor.fetchall()]
        for table in tables:
            cursor.execute(f"DROP TABLE [{schema_name}].[{table}]")
            print(f"Dropped table '{schema_name}.{table}'")

    cursor.execute(f"DROP SCHEMA [{schema_name}]")
    conn.commit()
    print(f"Dropped schema '{schema_name}'")
    return True


def get_column_info(conn, schema_name: str, table_name: str) -> List[Dict]:
    """Get column information for a table."""
    cursor = conn.cursor()
    cursor.execute(
        """SELECT c.name, t.name as type_name, c.max_length, c.is_nullable, c.is_identity
           FROM sys.columns c
           JOIN sys.types t ON c.user_type_id = t.user_type_id
           JOIN sys.tables tb ON c.object_id = tb.object_id
           JOIN sys.schemas s ON tb.schema_id = s.schema_id
           WHERE s.name = ? AND tb.name = ?
           ORDER BY c.column_id""",
        (schema_name, table_name)
    )
    return [
        {
            'name': row[0],
            'type': row[1],
            'max_length': row[2],
            'nullable': row[3],
            'is_identity': row[4]
        }
        for row in cursor.fetchall()
    ]


def import_csv(conn, csv_path: str, schema_name: str, table_name: str,
               create_table: bool = True, truncate: bool = False) -> int:
    """
    Import a CSV file into a database table.

    Args:
        conn: Database connection
        csv_path: Path to CSV file
        schema_name: Target schema
        table_name: Target table name
        create_table: Create table if it doesn't exist (infers types from data)
        truncate: Truncate table before loading

    Returns:
        Number of rows imported
    """
    cursor = conn.cursor()
    rows_imported = 0

    with open(csv_path, 'r', newline='', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        headers = reader.fieldnames

        if not headers:
            raise ValueError(f"CSV file {csv_path} has no headers")

        # Read all rows to infer types
        rows = list(reader)
        if not rows:
            print(f"CSV file {csv_path} is empty")
            return 0

        # Infer column types from data
        col_types = infer_column_types(headers, rows)

        # Create table if needed
        if create_table and not table_exists(conn, schema_name, table_name):
            create_table_sql = generate_create_table(schema_name, table_name, col_types)
            cursor.execute(create_table_sql)
            conn.commit()
            print(f"Created table '{schema_name}.{table_name}'")

        # Truncate if requested
        if truncate and table_exists(conn, schema_name, table_name):
            cursor.execute(f"TRUNCATE TABLE [{schema_name}].[{table_name}]")
            print(f"Truncated table '{schema_name}.{table_name}'")

        # Insert rows
        placeholders = ','.join(['?' for _ in headers])
        columns = ','.join([f'[{h}]' for h in headers])
        insert_sql = f"INSERT INTO [{schema_name}].[{table_name}] ({columns}) VALUES ({placeholders})"

        for row in rows:
            values = [convert_value(row.get(h, ''), col_types.get(h, 'NVARCHAR')) for h in headers]
            cursor.execute(insert_sql, values)
            rows_imported += 1

        conn.commit()

    print(f"Imported {rows_imported} rows into '{schema_name}.{table_name}'")
    return rows_imported


def infer_column_types(headers: List[str], rows: List[Dict]) -> Dict[str, str]:
    """Infer SQL Server column types from CSV data."""
    col_types = {}

    for header in headers:
        values = [row.get(header, '') for row in rows if row.get(header, '')]

        if not values:
            col_types[header] = 'NVARCHAR(255)'
            continue

        # Check if all values are integers
        try:
            [int(v) for v in values]
            max_val = max(abs(int(v)) for v in values)
            if max_val <= 2147483647:
                col_types[header] = 'INT'
            else:
                col_types[header] = 'BIGINT'
            continue
        except ValueError:
            pass

        # Check if all values are floats
        try:
            [float(v) for v in values]
            col_types[header] = 'DECIMAL(18,6)'
            continue
        except ValueError:
            pass

        # Check if all values look like dates
        import re
        date_pattern = r'^\d{4}-\d{2}-\d{2}$'
        if all(re.match(date_pattern, v) for v in values):
            col_types[header] = 'DATE'
            continue

        datetime_pattern = r'^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}'
        if all(re.match(datetime_pattern, v) for v in values):
            col_types[header] = 'DATETIME2'
            continue

        # Default to NVARCHAR with appropriate length
        max_len = max(len(v) for v in values)
        if max_len <= 50:
            col_types[header] = 'NVARCHAR(50)'
        elif max_len <= 255:
            col_types[header] = 'NVARCHAR(255)'
        else:
            col_types[header] = 'NVARCHAR(MAX)'

    return col_types


def generate_create_table(schema_name: str, table_name: str, col_types: Dict[str, str]) -> str:
    """Generate CREATE TABLE SQL statement."""
    columns = [f"[{col}] {dtype} NULL" for col, dtype in col_types.items()]
    return f"CREATE TABLE [{schema_name}].[{table_name}] (\n    " + ",\n    ".join(columns) + "\n)"


def convert_value(value: str, sql_type: str) -> Any:
    """Convert string value to appropriate Python type for SQL Server."""
    if value == '' or value is None:
        return None

    if 'INT' in sql_type:
        return int(value)
    elif 'DECIMAL' in sql_type or 'FLOAT' in sql_type:
        return float(value)
    else:
        return value


def export_csv(conn, schema_name: str, table_name: str, csv_path: str,
               query: str = None) -> int:
    """
    Export a table or query results to CSV.

    Args:
        conn: Database connection
        schema_name: Source schema (ignored if query provided)
        table_name: Source table (ignored if query provided)
        csv_path: Output CSV path
        query: Optional custom query

    Returns:
        Number of rows exported
    """
    cursor = conn.cursor()

    if query:
        cursor.execute(query)
    else:
        cursor.execute(f"SELECT * FROM [{schema_name}].[{table_name}]")

    columns = [desc[0] for desc in cursor.description]
    rows = cursor.fetchall()

    with open(csv_path, 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f, quoting=csv.QUOTE_NONNUMERIC)
        writer.writerow(columns)
        for row in rows:
            writer.writerow(['' if v is None else v for v in row])

    print(f"Exported {len(rows)} rows to '{csv_path}'")
    return len(rows)


def compare_csv_files(file1: str, file2: str, ignore_order: bool = True) -> tuple:
    """
    Compare two CSV files and return (match, differences).

    Returns:
        Tuple of (bool: files match, list: differences)
    """
    with open(file1, 'r', newline='', encoding='utf-8') as f1:
        reader1 = csv.DictReader(f1)
        rows1 = list(reader1)
        headers1 = reader1.fieldnames

    with open(file2, 'r', newline='', encoding='utf-8') as f2:
        reader2 = csv.DictReader(f2)
        rows2 = list(reader2)
        headers2 = reader2.fieldnames

    differences = []

    # Check headers
    if set(headers1) != set(headers2):
        differences.append(f"Headers differ: {headers1} vs {headers2}")

    # Check row count
    if len(rows1) != len(rows2):
        differences.append(f"Row count differs: {len(rows1)} vs {len(rows2)}")

    # Compare rows
    if ignore_order:
        # Sort by all columns for comparison
        def row_key(row):
            return tuple(str(row.get(h, '')) for h in sorted(headers1 or []))
        rows1_sorted = sorted(rows1, key=row_key)
        rows2_sorted = sorted(rows2, key=row_key)
    else:
        rows1_sorted = rows1
        rows2_sorted = rows2

    for i, (r1, r2) in enumerate(zip(rows1_sorted, rows2_sorted)):
        for h in headers1 or []:
            v1 = str(r1.get(h, ''))
            v2 = str(r2.get(h, ''))
            if v1 != v2:
                # Try numeric comparison for decimal precision differences
                try:
                    if float(v1) == float(v2):
                        continue  # Same numeric value, just different precision
                except (ValueError, TypeError):
                    pass
                differences.append(f"Row {i+1}, column '{h}': '{v1}' vs '{v2}'")

    return (len(differences) == 0, differences)


def main():
    """CLI interface for db_utils."""
    parser = argparse.ArgumentParser(description='Database utilities for integration tests')
    parser.add_argument('--server', required=True, help='Database server')
    parser.add_argument('--database', required=True, help='Database name')
    parser.add_argument('--user', required=True, help='Username')
    parser.add_argument('--password', required=True, help='Password')

    subparsers = parser.add_subparsers(dest='command', help='Command')

    # Test connection
    subparsers.add_parser('test', help='Test database connection')

    # Import CSV
    import_parser = subparsers.add_parser('import', help='Import CSV to table')
    import_parser.add_argument('--csv', required=True, help='CSV file path')
    import_parser.add_argument('--schema', required=True, help='Target schema')
    import_parser.add_argument('--table', required=True, help='Target table')
    import_parser.add_argument('--truncate', action='store_true', help='Truncate before load')

    # Export CSV
    export_parser = subparsers.add_parser('export', help='Export table to CSV')
    export_parser.add_argument('--csv', required=True, help='Output CSV path')
    export_parser.add_argument('--schema', required=True, help='Source schema')
    export_parser.add_argument('--table', required=True, help='Source table')
    export_parser.add_argument('--query', help='Custom query instead of table')

    # Compare CSVs
    compare_parser = subparsers.add_parser('compare', help='Compare two CSV files')
    compare_parser.add_argument('--file1', required=True, help='First CSV file')
    compare_parser.add_argument('--file2', required=True, help='Second CSV file')

    # Drop schema
    drop_parser = subparsers.add_parser('drop-schema', help='Drop a schema and all its objects')
    drop_parser.add_argument('--schema', required=True, help='Schema to drop')

    args = parser.parse_args()

    if args.command == 'test':
        success = test_connection(args.server, args.database, args.user, args.password)
        sys.exit(0 if success else 1)

    elif args.command == 'import':
        conn = get_connection(args.server, args.database, args.user, args.password)
        import_csv(conn, args.csv, args.schema, args.table, truncate=args.truncate)
        conn.close()

    elif args.command == 'export':
        conn = get_connection(args.server, args.database, args.user, args.password)
        export_csv(conn, args.schema, args.table, args.csv, query=args.query)
        conn.close()

    elif args.command == 'compare':
        match, diffs = compare_csv_files(args.file1, args.file2)
        if match:
            print("Files match!")
            sys.exit(0)
        else:
            print("Files differ:")
            for d in diffs[:10]:  # Show first 10 differences
                print(f"  {d}")
            if len(diffs) > 10:
                print(f"  ... and {len(diffs) - 10} more differences")
            sys.exit(1)

    elif args.command == 'drop-schema':
        conn = get_connection(args.server, args.database, args.user, args.password)
        drop_schema(conn, args.schema, cascade=True)
        conn.close()

    else:
        parser.print_help()
        sys.exit(1)


if __name__ == '__main__':
    main()
