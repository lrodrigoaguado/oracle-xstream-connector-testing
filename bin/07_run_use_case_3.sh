#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
USE_CASE_DIR="$PROJECT_DIR/sql/use_case_3"

# Source help functions
source "$SCRIPT_DIR/helpers.sh"

echo "------------------------------------------------------------------------"
echo "🧪 USE CASE 3: No-PK (Manual Key Derivation)"
echo "------------------------------------------------------------------------"
echo ""

# Get initial JOBS count
INITIAL_COUNT=$(get_postgres_count "JOBS" 2>/dev/null || echo "0")
echo "📊 Initial JOBS count in Postgres: $INITIAL_COUNT"
echo ""

# Step 1: Operations (Inserts/Updates)
echo "------------------------------------------------------------------------"
echo "📝 Step 1: Testing INSERT/UPDATE operations on JOBS"
echo "Inserting a new job and updating an existing one in Oracle..."
run_oracle_sql "$USE_CASE_DIR/01_operations.sql"
echo "Oracle operations successful"

# 1. Update confirmation (JOB_ID='AD_VP', MAX_SALARY=35000)
wait_for_postgres_update "JOBS" "\"JOB_ID\" = 'AD_VP'" "35000" "MAX_SALARY"

# 2. Count confirmation
EXPECTED_COUNT=$((INITIAL_COUNT + 1))
wait_for_replication "JOBS" "$EXPECTED_COUNT" "new job insert"
echo ""

# Step 2: Delete
echo "------------------------------------------------------------------------"
echo "🗑️ Step 2: Testing DELETE operation on JOBS"
echo "Removing a job record from the Oracle database..."
BEFORE_DELETE=$(get_postgres_count "JOBS" 2>/dev/null || echo "0")
START_DELETE=$(date +%s.%N)
run_oracle_sql "$USE_CASE_DIR/02_deletes.sql"
echo "Oracle delete successful"
EXPECTED_AFTER_DELETE=$((BEFORE_DELETE - 1))
wait_for_postgres_delete "JOBS" "$EXPECTED_AFTER_DELETE" "$START_DELETE"
echo ""

echo "------------------------------------------------------------------------"
echo -e "${GREEN}✅ USE CASE 3 COMPLETED SUCCESSFULLY${NC}"
echo "------------------------------------------------------------------------"
