#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
USE_CASE_DIR="$PROJECT_DIR/sql/use_case_1"

# Source help functions
source "$SCRIPT_DIR/helpers.sh"

echo "------------------------------------------------------------------------"
echo "🧪 USE CASE 1: Basic Data Flow (DML, DDL, Complex Types)"
echo "------------------------------------------------------------------------"
echo ""

# Get initial EMPLOYEES count
INITIAL_COUNT=$(get_postgres_count "EMPLOYEES" 2>/dev/null || echo "0")
echo "📊 Initial EMPLOYEES count in Postgres: $INITIAL_COUNT"
echo ""

# Step 1: Update
echo "------------------------------------------------------------------------"
echo "📝 Step 1: Testing UPDATE operation"
echo "Updating salary for Employee ID 1 in the Oracle database..."
run_oracle_sql "$USE_CASE_DIR/01_update.sql"
echo "Oracle update successful"
# Check for salary update to 90000.00 for employee 1
wait_for_postgres_update "EMPLOYEES" "\"EMPLOYEE_ID\" = 1" "90000" "SALARY"
echo ""

# Step 2: Delete
echo "------------------------------------------------------------------------"
echo "🗑️ Step 2: Testing DELETE operation"
echo "Removing one employee record from the Oracle database..."
BEFORE_DELETE=$(get_postgres_count "EMPLOYEES" 2>/dev/null || echo "0")
START_DELETE=$(date +%s.%N)
run_oracle_sql "$USE_CASE_DIR/02_delete.sql"
echo "Oracle delete successful"
EXPECTED_AFTER_DELETE=$((BEFORE_DELETE - 1))
wait_for_postgres_delete "EMPLOYEES" "$EXPECTED_AFTER_DELETE" "$START_DELETE"
echo ""

# Step 3: Schema Changes
echo "------------------------------------------------------------------------"
echo "🔧 Step 3: Testing SCHEMA CHANGES (DDL)"
echo "Adding a new column and inserting a record into the Oracle database..."
run_oracle_sql "$USE_CASE_DIR/03_schema_changes.sql"
echo "Oracle schema changes successful"
echo "⏳ Waiting for schema change propagation (checking topics)..."
sleep 5
echo -e "${GREEN}✅ Schema changes applied. Check __orcl-schema-changes topic in Control Center.${NC}"
echo ""

# Step 4: Complex Types
echo "------------------------------------------------------------------------"
echo "📦 Step 4: Testing COMPLEX DATA TYPES"
echo "Inserting a record with XML, CLOB, and LONG types into Oracle..."
run_oracle_sql "$USE_CASE_DIR/04_complex_types.sql"
echo "Oracle complex types insert successful"

# Expect 2 rows now (Initial seed + this insert)
wait_for_replication "DATA_TYPES_TEST" "2" "complex types insert"
echo ""

echo "------------------------------------------------------------------------"
echo -e "${GREEN}✅ USE CASE 1 COMPLETED SUCCESSFULLY${NC}"
echo "------------------------------------------------------------------------"
