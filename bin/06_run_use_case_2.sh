#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
USE_CASE_DIR="$PROJECT_DIR/sql/use_case_2"

# Source help functions
source "$SCRIPT_DIR/helpers.sh"

echo "------------------------------------------------------------------------"
echo "🧪 USE CASE 2: No-PK with Unique Index (Auto-Key Derivation)"
echo "------------------------------------------------------------------------"
echo ""

# Get initial DEPARTMENTS count
INITIAL_COUNT=$(get_postgres_count "DEPARTMENTS" 2>/dev/null || echo "0")
echo "📊 Initial DEPARTMENTS count in Postgres: $INITIAL_COUNT"
echo ""

# Step 1: Operations (Inserts/Updates)
echo "------------------------------------------------------------------------"
echo "📝 Step 1: Testing INSERT/UPDATE operations on DEPARTMENTS"
echo "Inserting a new department and updating an existing one in Oracle..."
run_oracle_sql "$USE_CASE_DIR/01_operations.sql"
echo "Oracle operations successful"

# 1. Update confirmation (DEPT_ID=20, DEPT_NAME='Legal')
wait_for_postgres_update "DEPARTMENTS" "\"DEPT_ID\" = 20" "Legal" "DEPT_NAME"

# 2. Count confirmation
EXPECTED_COUNT=$((INITIAL_COUNT + 1))
wait_for_replication "DEPARTMENTS" "$EXPECTED_COUNT" "new department insert"
echo ""

# Step 2: Delete
echo "------------------------------------------------------------------------"
echo "🗑️ Step 2: Testing DELETE operation on DEPARTMENTS"
echo "Removing a department record from the Oracle database..."
BEFORE_DELETE=$(get_postgres_count "DEPARTMENTS" 2>/dev/null || echo "0")
START_DELETE=$(date +%s.%N)
run_oracle_sql "$USE_CASE_DIR/02_deletes.sql"
echo "Oracle delete successful"
EXPECTED_AFTER_DELETE=$((BEFORE_DELETE - 1))
wait_for_postgres_delete "DEPARTMENTS" "$EXPECTED_AFTER_DELETE" "$START_DELETE"
echo ""

echo "------------------------------------------------------------------------"
echo -e "${GREEN}✅ USE CASE 2 COMPLETED SUCCESSFULLY${NC}"
echo "------------------------------------------------------------------------"
