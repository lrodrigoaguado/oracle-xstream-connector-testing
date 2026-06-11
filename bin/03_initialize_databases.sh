#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "🚀 Initializing Databases..."

# 1. Oracle Initialization - Create Tables
echo "----------------------------------------------------------------"
echo "🟢 Step 1/3: Creating Oracle Tables..."
if [ -f "$PROJECT_DIR/sql/setup/01_create_tables.sql" ]; then
    cat "$PROJECT_DIR/sql/setup/01_create_tables.sql" | docker exec -i oracle-19 sqlplus -S demo/DemoPass123@//localhost:1521/SOURCEPDB
    echo "✅ Tables created."
else
    echo "⚠️ sql/setup/01_create_tables.sql not found!"
    exit 1
fi

# 2. Oracle Initialization - Insert Data
echo "----------------------------------------------------------------"
echo "🟢 Step 2/3: Inserting Initial Data into Oracle..."
if [ -f "$PROJECT_DIR/sql/setup/02_insert_data.sql" ]; then
    cat "$PROJECT_DIR/sql/setup/02_insert_data.sql" | docker exec -i oracle-19 sqlplus -S demo/DemoPass123@//localhost:1521/SOURCEPDB
    echo "✅ Data inserted."
else
    echo "⚠️ sql/setup/02_insert_data.sql not found!"
    exit 1
fi

echo "----------------------------------------------------------------"
echo "✅ Oracle Databases Initialized Successfully!"

# 3. Oracle Sink Initialization - Create Tables with Referential Integrity and complex-type triggers
echo "----------------------------------------------------------------"
echo "🔵 Step 3/3: Pre-creating the full mirrored sink schema in SINKPDB.DEMO (7 tables, FK + complex-type trigger)..."
if [ -f "$PROJECT_DIR/sql/setup/03_create_oracle_sink_tables.sql" ]; then
    cat "$PROJECT_DIR/sql/setup/03_create_oracle_sink_tables.sql" | docker exec -i oracle-19 sqlplus -S demo/DemoPass123@//localhost:1521/SINKPDB
    echo "✅ Oracle sink tables created."
else
    echo "⚠️ sql/setup/03_create_oracle_sink_tables.sql not found!"
    exit 1
fi

echo "----------------------------------------------------------------"
echo "✅ All Databases Initialized Successfully!"
echo ""
echo "ℹ️  The sink connector runs with auto.create=false: every target table above was created here, mirroring the source (see sql/setup/03_create_oracle_sink_tables.sql for the deliberate differences)."
