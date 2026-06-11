#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
USE_CASE_DIR="$PROJECT_DIR/sql/use_case_1"

source "$SCRIPT_DIR/helpers.sh"

uc_intro "1" "Basic data flow — DML, DDL & complex types" \
"An UPDATE, a DELETE, an online schema change (ADD/DROP column) and a row of
  complex types (XML, CLOB, LONG, BLOB) all flow from SOURCEPDB to SINKPDB."

# Step 1 — UPDATE
uc_step "Step 1/4" "UPDATE an existing row"
uc_source "Raise employee 1's salary to 90,000 and move them to 'Senior Engineering'."
run_oracle_sql "$USE_CASE_DIR/01_update.sql"
wait_for_sink_update "EMPLOYEES" "\"EMPLOYEE_ID\" = 1" "90000" "SALARY"

# Step 2 — DELETE
uc_step "Step 2/4" "DELETE a row"
uc_source "Delete employee 3."
BEFORE_DELETE=$(get_sink_count "EMPLOYEES" 2>/dev/null || echo "0")
START_DELETE=$(date +%s.%N)
run_oracle_sql "$USE_CASE_DIR/02_delete.sql"
wait_for_sink_delete "EMPLOYEES" "$((BEFORE_DELETE - 1))" "$START_DELETE"

# Step 3 — Schema change (DDL) + insert exercising the new column
uc_step "Step 3/4" "Online schema change (DDL)"
uc_source "ADD column PHONE_NUMBER, DROP column HIRE_DATE, then INSERT employee 4 (with a phone number)."
run_oracle_sql "$USE_CASE_DIR/03_schema_changes.sql"
wait_for_sink_update "EMPLOYEES" "\"EMPLOYEE_ID\" = 4" "555-1234" "PHONE_NUMBER"
uc_note "auto.evolve added the PHONE_NUMBER column to the sink table on the fly."

# Step 4 — Complex data types
uc_step "Step 4/4" "Complex data types"
uc_source "INSERT a row carrying XML, CLOB, LONG and BLOB values."
run_oracle_sql "$USE_CASE_DIR/04_complex_types.sql"
wait_for_replication "DATA_TYPES_TEST" "2" "complex types insert"

uc_pass "1"
