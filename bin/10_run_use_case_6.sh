#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
USE_CASE_DIR="$PROJECT_DIR/sql/use_case_6"

source "$SCRIPT_DIR/helpers.sh"

uc_intro "6" "Partial LOB update — custom SMT" \
"When only a non-LOB column changes, Oracle XStream emits a placeholder for the
  unchanged LOB instead of its value. A custom SMT strips that placeholder so
  the sink keeps the CLOB it already has, rather than overwriting it with junk."

# Preparation — set a known baseline for the CLOB on the sink
uc_step "Setup" "Set a known CLOB baseline on the sink"
docker exec -i oracle-19 sqlplus -S demo/DemoPass123@//localhost:1521/SINKPDB > /dev/null 2>&1 <<'SQL'
WHENEVER SQLERROR EXIT FAILURE;
UPDATE "DATA_TYPES_TEST" SET "CLOB_COL" = 'Initial baseline content' WHERE "ID" = 2;
COMMIT;
EXIT;
SQL
uc_note "Baseline CLOB_COL for ID 2 → 'Initial baseline content'."

# Step 1 — Update only the non-LOB column
uc_step "Step 1/1" "UPDATE a non-LOB column on a row that has a CLOB"
uc_source "Set NUMBER_COL = 99999.99 for ID 2 (CLOB_COL is NOT touched)."
run_oracle_sql "$USE_CASE_DIR/01_partial_update.sql"
wait_for_sink_update "DATA_TYPES_TEST" "\"ID\" = 2" "99999.99" "NUMBER_COL"

CLOB_CONTENT=$(get_sink_value "DATA_TYPES_TEST" "\"ID\" = 2" "CLOB_COL")
if [[ "$CLOB_CONTENT" == "Initial baseline content" ]]; then
    uc_ok "CLOB_COL preserved — the SMT dropped the placeholder."
    uc_pass "6"
else
    uc_bad "CLOB_COL changed unexpectedly: '$CLOB_CONTENT'"
    [[ "$CLOB_CONTENT" == "__cflt_unavailable_value" ]] && uc_bad "Placeholder leaked through — the SMT did not remove it."
    exit 1
fi
