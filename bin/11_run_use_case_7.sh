#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
USE_CASE_DIR="$PROJECT_DIR/sql/use_case_7"

source "$SCRIPT_DIR/helpers.sh"

SINK_CONNECTOR="JdbcSinkConnector"
DLQ_TOPIC="JDBC_SINK_DLQ"

uc_intro "7" "No key at all — null key routed to the DLQ" \
"AUDIT_LOG has no PK, no unique index and no candidate key column, and the source
  connector has no message.key.columns for it — so every record is emitted with a
  NULL key. The sink's custom RequireNonNullKey SMT diverts each one to the DLQ,
  so the task keeps RUNNING instead of crashing inside put()."

DLQ_BEFORE=$(get_dlq_count "$DLQ_TOPIC")
SINK_COUNT_BEFORE=$(get_sink_count "AUDIT_LOG" 2>/dev/null || echo "0")

# Step 1 — produce null-key records and watch them land in the DLQ
uc_step "Step 1/1" "INSERT 3 audit rows (each becomes a NULL-key record)"
uc_source "INSERT 3 rows into AUDIT_LOG (LOGIN, UPDATE, DELETE audit events)."
run_oracle_sql "$USE_CASE_DIR/01_operations.sql"
wait_for_dlq "$DLQ_TOPIC" "$((DLQ_BEFORE + 3))"

# The records must NOT have been written to the sink table …
SINK_COUNT_AFTER=$(get_sink_count "AUDIT_LOG" 2>/dev/null || echo "0")
if [ "$SINK_COUNT_AFTER" == "$SINK_COUNT_BEFORE" ]; then
    uc_ok "AUDIT_LOG row count unchanged (${SINK_COUNT_AFTER}) — records were diverted, not written."
else
    uc_bad "AUDIT_LOG changed from ${SINK_COUNT_BEFORE} to ${SINK_COUNT_AFTER} — records should not have landed."
    exit 1
fi

# … and the sink connector must still be alive (this is the whole point).
STATE=$(get_connector_state "$SINK_CONNECTOR")
FAILED_TASKS=$(get_failed_task_count "$SINK_CONNECTOR")
if [ "$STATE" == "RUNNING" ] && [ "${FAILED_TASKS:-0}" -eq 0 ]; then
    uc_ok "Sink connector still RUNNING with 0 failed tasks — the pipeline never stopped."
else
    uc_bad "Sink connector state=${STATE}, failed tasks=${FAILED_TASKS} — it should have stayed RUNNING."
    exit 1
fi

DLQ_REASON=$(show_dlq_error "$DLQ_TOPIC" || true)
[ -n "$DLQ_REASON" ] && uc_note "DLQ header → ${DLQ_REASON}"

uc_pass "7"
