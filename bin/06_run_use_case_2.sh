#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
USE_CASE_DIR="$PROJECT_DIR/sql/use_case_2"

source "$SCRIPT_DIR/helpers.sh"

uc_intro "2" "No primary key, but a unique index" \
"DEPARTMENTS has no PK — only a unique index on DEPT_ID. The connector detects
  that index and uses it as the message key, so UPDATE and DELETE replicate
  correctly (on the target, DEPT_ID is promoted to a real PRIMARY KEY)."

INITIAL_COUNT=$(get_sink_count "DEPARTMENTS" 2>/dev/null || echo "0")

# Step 1 — INSERT + UPDATE
uc_step "Step 1/2" "INSERT and UPDATE"
uc_source "INSERT department 40 (Finance)."
uc_source "UPDATE department 20's name to 'Legal'."
run_oracle_sql "$USE_CASE_DIR/01_operations.sql"
wait_for_sink_update "DEPARTMENTS" "\"DEPT_ID\" = 20" "Legal" "DEPT_NAME"
wait_for_replication "DEPARTMENTS" "$((INITIAL_COUNT + 1))" "new department insert"

# Step 2 — DELETE
uc_step "Step 2/2" "DELETE"
uc_source "Delete department 20."
BEFORE_DELETE=$(get_sink_count "DEPARTMENTS" 2>/dev/null || echo "0")
START_DELETE=$(date +%s.%N)
run_oracle_sql "$USE_CASE_DIR/02_deletes.sql"
wait_for_sink_delete "DEPARTMENTS" "$((BEFORE_DELETE - 1))" "$START_DELETE"

uc_pass "2"
