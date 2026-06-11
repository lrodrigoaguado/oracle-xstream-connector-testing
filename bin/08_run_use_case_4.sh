#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
USE_CASE_DIR="$PROJECT_DIR/sql/use_case_4"

source "$SCRIPT_DIR/helpers.sh"

FAILED=0

uc_intro "4" "CLOB replication — populated, NULL and empty" \
"CLOB_TEST is created mid-demo and picked up automatically. Oracle stores an
  empty string AS NULL, so EMPTY_CLOB() reaches the sink as NULL — this use case
  shows exactly how each CLOB state survives replication."

# Preparation — fresh source table, empty sink table (no narration, no SQL noise)
uc_step "Setup" "Create the source table and clear the sink"
docker exec -i oracle-19 sqlplus -S demo/DemoPass123@//localhost:1521/SOURCEPDB > /dev/null 2>&1 <<'SQL'
BEGIN EXECUTE IMMEDIATE 'DROP TABLE DEMO.CLOB_TEST';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
/
COMMIT;
SQL
run_oracle_sql "$USE_CASE_DIR/01_create_tables.sql"
# Sink CLOB_TEST is pre-created by 03_initialize_databases.sh (CLOB_REQUIRED is
# deliberately nullable there). Just clear any rows from a previous run.
docker exec -i oracle-19 sqlplus -S demo/DemoPass123@//localhost:1521/SINKPDB > /dev/null 2>&1 <<'SQL'
WHENEVER SQLERROR EXIT FAILURE;
DELETE FROM "CLOB_TEST";
COMMIT;
EXIT;
SQL
uc_note "Source table created, sink table emptied."
sleep 5

# Step 1 — INSERT every combination
uc_step "Step 1/2" "INSERT three rows covering every CLOB state"
uc_source "ID 1 — nullable = text          · required = EMPTY_CLOB()"
uc_source "ID 2 — nullable = NULL          · required = text"
uc_source "ID 3 — nullable = NULL          · required = EMPTY_CLOB()"
run_oracle_sql "$USE_CASE_DIR/02_inserts.sql"
wait_for_replication "CLOB_TEST" "3" "initial inserts"

ID1_NULLABLE=$(get_sink_value "CLOB_TEST" "\"ID\" = 1" "CLOB_NULLABLE")
ID1_REQUIRED=$(get_sink_value "CLOB_TEST" "\"ID\" = 1" "CLOB_REQUIRED")
ID2_NULLABLE=$(get_sink_value "CLOB_TEST" "\"ID\" = 2" "CLOB_NULLABLE")
ID2_REQUIRED=$(get_sink_value "CLOB_TEST" "\"ID\" = 2" "CLOB_REQUIRED")
ID3_REQUIRED=$(get_sink_value "CLOB_TEST" "\"ID\" = 3" "CLOB_REQUIRED")

if [[ "$ID1_NULLABLE" == "This is a nullable CLOB" && "$ID1_REQUIRED" == "" ]]; then
    uc_ok "ID 1 — nullable kept its text · required arrived as NULL (was EMPTY_CLOB)"
else
    uc_bad "ID 1 — unexpected (nullable='$ID1_NULLABLE', required='$ID1_REQUIRED')"; FAILED=1
fi
if [[ ( -z "$ID2_NULLABLE" || "$ID2_NULLABLE" == "null" ) && "$ID2_REQUIRED" == "Required CLOB cannot be null" ]]; then
    uc_ok "ID 2 — nullable arrived as NULL · required kept its text"
else
    uc_bad "ID 2 — unexpected (nullable='$ID2_NULLABLE', required='$ID2_REQUIRED')"; FAILED=1
fi
if [[ "$ID3_REQUIRED" == "" ]]; then
    uc_ok "ID 3 — required arrived as NULL (EMPTY_CLOB preserved as NULL)"
else
    uc_bad "ID 3 — required should be NULL, got '$ID3_REQUIRED'"; FAILED=1
fi

# Step 2 — UPDATE in both directions
uc_step "Step 2/2" "UPDATE each CLOB in both directions"
uc_source "ID 1 — nullable → NULL          · required → 'Updated Required'"
uc_source "ID 2 — nullable → text          · required → EMPTY_CLOB()"
uc_source "ID 3 — change a non-CLOB column only (CLOBs must stay untouched)"
run_oracle_sql "$USE_CASE_DIR/03_updates.sql"
wait_for_sink_update "CLOB_TEST" "\"ID\" = 2" "Updated to a value" "CLOB_NULLABLE"
wait_for_sink_update "CLOB_TEST" "\"ID\" = 1" "Updated Required" "CLOB_REQUIRED"

ID1_NULLABLE_NEW=$(get_sink_value "CLOB_TEST" "\"ID\" = 1" "CLOB_NULLABLE")
ID1_REQUIRED_NEW=$(get_sink_value "CLOB_TEST" "\"ID\" = 1" "CLOB_REQUIRED")
ID2_NULLABLE_NEW=$(get_sink_value "CLOB_TEST" "\"ID\" = 2" "CLOB_NULLABLE")
ID2_REQUIRED_NEW=$(get_sink_value "CLOB_TEST" "\"ID\" = 2" "CLOB_REQUIRED")
ID3_DESCR_NEW=$(get_sink_value "CLOB_TEST" "\"ID\" = 3" "DESCRIPTION")

if [[ -z "$ID1_NULLABLE_NEW" && "$ID1_REQUIRED_NEW" == "Updated Required" ]]; then
    uc_ok "ID 1 — nullable → NULL · required → 'Updated Required'"
else
    uc_bad "ID 1 — unexpected (nullable='$ID1_NULLABLE_NEW', required='$ID1_REQUIRED_NEW')"; FAILED=1
fi
if [[ "$ID2_NULLABLE_NEW" == "Updated to a value" && "$ID2_REQUIRED_NEW" == "" ]]; then
    uc_ok "ID 2 — nullable → 'Updated to a value' · required → NULL (EMPTY_CLOB)"
else
    uc_bad "ID 2 — unexpected (nullable='$ID2_NULLABLE_NEW', required='$ID2_REQUIRED_NEW')"; FAILED=1
fi
if [[ "$ID3_DESCR_NEW" == "Updated Description" ]]; then
    uc_ok "ID 3 — non-CLOB column updated, CLOBs left untouched"
else
    uc_bad "ID 3 — non-CLOB update failed, got '$ID3_DESCR_NEW'"; FAILED=1
fi

[ "$FAILED" -eq 0 ] || exit 1
uc_pass "4"
