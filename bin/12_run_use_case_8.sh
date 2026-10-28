#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
USE_CASE_DIR="$PROJECT_DIR/sql/use_case_8"
SIGNAL_DIR="$PROJECT_DIR/etc/signals"

source "$SCRIPT_DIR/helpers.sh"

uc_intro "8" "On-demand snapshot — recover a table with a Kafka signal" \
"The replicated EMPLOYEES data is lost in SINKPDB. Instead of restarting the connector
  or resetting offsets, we publish ONE message to the 'xstream-signals' topic: the source
  connector pauses streaming, re-reads the table from SOURCEPDB, republishes every row and
  resumes streaming. A second signal re-snapshots only the rows matching a filter."

# Print the sink's EMPLOYEES table, indented under the current step.   $1 = caption
show_sink_employees() {
    uc_note "$1"
    docker exec -i oracle-19 sqlplus -S demo/DemoPass123@//localhost:1521/SINKPDB \
        < "$USE_CASE_DIR/show_sink_employees.sql" | sed '/^$/d; s/^/      /'
}

# Preflight — the signal topic is created by 04_deploy_connectors.sh
if ! docker exec broker1 kafka-topics --bootstrap-server broker1:29092 \
        --describe --topic "$SIGNAL_TOPIC" > /dev/null 2>&1; then
    uc_bad "Topic '${SIGNAL_TOPIC}' not found — re-run ./bin/04_deploy_connectors.sh first."
    exit 1
fi

# Setup — remove the employee a previous run added, so step 3 inserts a genuinely new row
uc_step "Setup" "Clear the test employee from any previous run"
run_oracle_sql "$USE_CASE_DIR/00_cleanup.sql"
SOURCE_COUNT=$(source_query "SELECT COUNT(*) FROM DEMO.EMPLOYEES;")
wait_for_replication "EMPLOYEES" "$SOURCE_COUNT" "cleanup of employee 8" 60

SOURCE_COUNT=$(source_query "SELECT COUNT(*) FROM DEMO.EMPLOYEES;")
if [ "${SOURCE_COUNT:-0}" -eq 0 ]; then
    uc_bad "SOURCEPDB.DEMO.EMPLOYEES is empty — nothing to snapshot."
    exit 1
fi

# Step 1 — lose the data in the sink
uc_step "Step 1/4" "Lose the replicated data in the sink"
uc_source "Nothing changes on the source: EMPLOYEES still holds ${SOURCE_COUNT} rows."
show_sink_employees "SINKPDB.DEMO.EMPLOYEES — starting point, in sync with the source:"
uc_note "Simulating an incident: every row of EMPLOYEES is deleted directly in SINKPDB."
run_sink_sql "$USE_CASE_DIR/01_wipe_sink.sql"
SINK_COUNT=$(get_sink_count "EMPLOYEES")
if [ "$SINK_COUNT" -eq 0 ]; then
    uc_ok "SINKPDB.DEMO.EMPLOYEES is now empty (source: ${SOURCE_COUNT} rows)."
    show_sink_employees "SINKPDB.DEMO.EMPLOYEES now:"
else
    uc_bad "Sink still has ${SINK_COUNT} rows — the wipe did not work."
    exit 1
fi

# Step 2 — full snapshot
uc_step "Step 2/4" "Send a signal: full snapshot of DEMO.EMPLOYEES"
uc_source "Publish an 'execute-snapshot' signal for SOURCEPDB.DEMO.EMPLOYEES."
send_signal "$SIGNAL_DIR/snapshot-employees.json"
wait_for_replication "EMPLOYEES" "$SOURCE_COUNT" "snapshot" 120
show_sink_employees "SINKPDB.DEMO.EMPLOYEES now — every row re-sent by the snapshot:"

# Step 3 — streaming continues
uc_step "Step 3/4" "Streaming resumes after the snapshot"
uc_source "INSERT a NEW employee (id 8) — a regular change event."
run_oracle_sql "$USE_CASE_DIR/02_new_employee.sql"
SOURCE_COUNT=$((SOURCE_COUNT + 1))
wait_for_sink_update "EMPLOYEES" "\"EMPLOYEE_ID\" = 8" "Grace" "FIRST_NAME"
show_sink_employees "SINKPDB.DEMO.EMPLOYEES now — a new row (employee 8) arrived as a regular change:"
uc_note "The connector went back to normal CDC once the snapshot finished."

# Step 4 — filtered snapshot
uc_step "Step 4/4" "Targeted snapshot: only the Engineering rows"
uc_note "Simulating a partial loss: only the Engineering rows are deleted in SINKPDB."
run_sink_sql "$USE_CASE_DIR/03_wipe_sink_engineering.sql"
PARTIAL_COUNT=$(get_sink_count "EMPLOYEES")
if [ "$PARTIAL_COUNT" -ge "$SOURCE_COUNT" ]; then
    uc_bad "Sink still has all ${PARTIAL_COUNT} rows — the partial wipe did not work."
    exit 1
fi
show_sink_employees "SINKPDB.DEMO.EMPLOYEES now — the Engineering rows are gone:"
uc_source "Publish a signal with an 'additional-conditions' filter (DEPARTMENT LIKE '%Engineering')."
send_signal "$SIGNAL_DIR/snapshot-employees-engineering.json"
wait_for_replication "EMPLOYEES" "$SOURCE_COUNT" "filtered snapshot" 120
show_sink_employees "SINKPDB.DEMO.EMPLOYEES now — only the Engineering rows were re-sent:"

uc_pass "8"
