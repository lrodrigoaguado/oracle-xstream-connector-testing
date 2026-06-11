#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
USE_CASE_DIR="$PROJECT_DIR/sql/use_case_3"

source "$SCRIPT_DIR/helpers.sh"

uc_intro "3" "No key at all — key derived at the source" \
"JOBS has neither a PK nor a unique index. message.key.columns tells the
  connector to use JOB_ID as the key, so UPDATE and DELETE still replicate
  (on the target, JOB_ID is promoted to a real PRIMARY KEY)."

INITIAL_COUNT=$(get_sink_count "JOBS" 2>/dev/null || echo "0")

# Step 1 — INSERT + UPDATE
uc_step "Step 1/2" "INSERT and UPDATE"
uc_source "INSERT job AD_VP (Administration Vice President)."
uc_source "UPDATE job AD_VP's max salary to 35,000."
run_oracle_sql "$USE_CASE_DIR/01_operations.sql"
wait_for_sink_update "JOBS" "\"JOB_ID\" = 'AD_VP'" "35000" "MAX_SALARY"
wait_for_replication "JOBS" "$((INITIAL_COUNT + 1))" "new job insert"

# Step 2 — DELETE
uc_step "Step 2/2" "DELETE"
uc_source "Delete job ST_CLERK."
BEFORE_DELETE=$(get_sink_count "JOBS" 2>/dev/null || echo "0")
START_DELETE=$(date +%s.%N)
run_oracle_sql "$USE_CASE_DIR/02_deletes.sql"
wait_for_sink_delete "JOBS" "$((BEFORE_DELETE - 1))" "$START_DELETE"

uc_pass "3"
