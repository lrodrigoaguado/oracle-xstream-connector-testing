#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "🚀 Initializing Databases..."

# 1. Oracle Initialization - Create Tables
echo "----------------------------------------------------------------"
echo "🟢 Step 1/3: Creating Oracle Tables..."
if [ -f "$PROJECT_DIR/sql/setup/01_create_tables.sql" ]; then
    cat "$PROJECT_DIR/sql/setup/01_create_tables.sql" | docker exec -i oracle-xe sqlplus -S demo/DemoPass123@//localhost:1521/XEPDB1
    echo "✅ Tables created."
else
    echo "⚠️ sql/setup/01_create_tables.sql not found!"
    exit 1
fi

# 2. Oracle Initialization - Insert Data
echo "----------------------------------------------------------------"
echo "🟢 Step 2/3: Inserting Initial Data into Oracle..."
if [ -f "$PROJECT_DIR/sql/setup/02_insert_data.sql" ]; then
    cat "$PROJECT_DIR/sql/setup/02_insert_data.sql" | docker exec -i oracle-xe sqlplus -S demo/DemoPass123@//localhost:1521/XEPDB1
    echo "✅ Data inserted."
else
    echo "⚠️ sql/setup/02_insert_data.sql not found!"
    exit 1
fi

echo "----------------------------------------------------------------"
echo "✅ Oracle Databases Initialized Successfully!"

# 3. Postgres Initialization - Create Tables with Referential Integrity
echo "----------------------------------------------------------------"
echo "🔵 Step 3/3: Creating Postgres Tables (with FK constraints for Use Case 4)..."
if [ -f "$PROJECT_DIR/sql/setup/03_create_postgres_tables.sql" ]; then
    cat "$PROJECT_DIR/sql/setup/03_create_postgres_tables.sql" | docker exec -i postgres psql -U test-connector -d test-connector
    echo "✅ Postgres tables created."
else
    echo "⚠️ sql/setup/03_create_postgres_tables.sql not found!"
    exit 1
fi

echo "----------------------------------------------------------------"
echo "✅ All Databases Initialized Successfully!"
echo ""
echo "ℹ️  Other Postgres tables will be auto-created by the JDBC Sink Connector (auto.create=true)."
