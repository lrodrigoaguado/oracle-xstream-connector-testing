#!/bin/bash

# Shared colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ─────────────────────────────────────────────────────────────────────────
# Presentation helpers — keep all six use-case scripts visually consistent.
# Each script narrates: what it tests → what changes on the SOURCE → when it
# lands on the SINK (the wait_* helpers report the latency) → the verdict.
# ─────────────────────────────────────────────────────────────────────────
HEAVY=$(printf '═%.0s' {1..72})
RULE=$(printf '─%.0s' {1..72})

# Opening banner + a one-paragraph "what this tests".
#   $1 = use-case number   $2 = title   $3 = description paragraph
uc_intro() {
    echo ""
    echo -e "${BOLD}${CYAN}${HEAVY}${NC}"
    echo -e "${BOLD}${CYAN}  🧪  USE CASE $1 — $2${NC}"
    echo -e "${BOLD}${CYAN}${HEAVY}${NC}"
    echo ""
    echo -e "  ${DIM}$3${NC}"
}

# Step heading.   $1 = label (e.g. "Step 1/3" or "Setup")   $2 = what it does
uc_step() {
    echo ""
    echo -e "  ${BOLD}▶  $1 — $2${NC}"
    echo -e "  ${DIM}${RULE:0:69}${NC}"
}

# A change applied on the SOURCE database (plain-English).
uc_source() {
    echo -e "    📤 ${YELLOW}SOURCE${NC}  $1"
}

# A verified outcome on the SINK (for checks the wait_* helpers don't cover).
uc_ok()   { echo -e "    ✅ ${GREEN}SINK${NC}    $1"; }
uc_bad()  { echo -e "    ❌ ${RED}SINK${NC}    $1"; }

# A dim, secondary note.
uc_note() { echo -e "    ${DIM}$1${NC}"; }

# Closing banner.   $1 = use-case number
uc_pass() {
    echo ""
    echo -e "${BOLD}${GREEN}${HEAVY}${NC}"
    echo -e "${BOLD}${GREEN}  ✅  USE CASE $1 PASSED${NC}"
    echo -e "${BOLD}${GREEN}${HEAVY}${NC}"
    echo ""
}

# All sink-side queries run against the SINKPDB.DEMO schema in the same Oracle
# container that hosts the source SOURCEPDB. Source-side queries continue to
# use SOURCEPDB via run_oracle_sql below.

# Helper function to run Oracle SQL against the SOURCE PDB (silently by default)
run_oracle_sql() {
    local sql_file="$1"
    local silent="${2:-true}"

    if [ "$silent" == "true" ]; then
        cat "$sql_file" | docker exec -i oracle-19 sqlplus -S demo/DemoPass123@//localhost:1521/SOURCEPDB > /dev/null 2>&1
    else
        echo -e "${YELLOW}📤 Executing: $(basename "$sql_file")${NC}"
        cat "$sql_file" | docker exec -i oracle-19 sqlplus -S demo/DemoPass123@//localhost:1521/SOURCEPDB
    fi
}

# Run a single SELECT against SINKPDB.DEMO and return the bare value.
# Trims leading/trailing whitespace via xargs without collapsing internal spaces.
sink_query() {
    local sql="$1"
    docker exec -i oracle-19 sqlplus -S demo/DemoPass123@//localhost:1521/SINKPDB <<SQL 2>/dev/null | xargs
SET HEADING OFF
SET FEEDBACK OFF
SET PAGESIZE 0
SET LINESIZE 32767
SET TRIMSPOOL ON
SET TRIMOUT ON
WHENEVER SQLERROR EXIT FAILURE;
$sql
EXIT;
SQL
}

# Helper function to get sink row count
get_sink_count() {
    local table="$1"
    local count
    count=$(sink_query "SELECT COUNT(*) FROM \"$table\";")
    echo "${count:-0}"
}

# Helper function to get a single value from the sink
get_sink_value() {
    local table="$1"
    local condition="$2"
    local column="$3"
    sink_query "SELECT \"$column\" FROM \"$table\" WHERE $condition;"
}

# Compare two values, treating them as numbers when both look numeric. This is
# needed because the sink's numeric columns are auto-created as a floating-point
# Oracle type (the source uses decimal.handling.mode=double), so sqlplus renders
# e.g. 90000 as "9.0E+004". A literal string compare against "90000" would never
# match even though the value replicated correctly. Falls back to string equality
# for non-numeric values.
values_match() {
    local a="$1" b="$2"
    [ "$a" == "$b" ] && return 0
    local num_re='^[-+]?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?$'
    if [[ "$a" =~ $num_re && "$b" =~ $num_re ]]; then
        awk -v x="$a" -v y="$b" 'BEGIN { exit !((x+0)==(y+0)) }'
        return $?
    fi
    return 1
}

# Helper function to wait for an UPDATE to land in the sink and report latency
# (SOURCETIMESTAMP -> SINKTIMESTAMP, in seconds).
wait_for_sink_update() {
    local table=$1
    local condition=$2
    local expected_val=$3
    local check_column=$4
    local timeout=${5:-30}
    local start_time=$(date +%s)

    echo -n "    ⏳ Waiting for the sink … "
    while true; do
        current_val=$(get_sink_value "$table" "$condition" "$check_column")
        if values_match "$current_val" "$expected_val"; then
            # Oracle equivalent of Postgres' extract(epoch from ...): cast each
            # TIMESTAMP to DATE and subtract DATE '1970-01-01' to get days,
            # multiply by 86400 to get seconds.
            local ts_data
            ts_data=$(sink_query "SELECT (CAST(\"SOURCETIMESTAMP\" AS DATE) - DATE '1970-01-01') * 86400 || ' ' || (CAST(\"SINKTIMESTAMP\" AS DATE) - DATE '1970-01-01') * 86400 FROM \"$table\" WHERE $condition;")

            local src_ts=$(echo "$ts_data" | awk '{print $1}')
            local snk_ts=$(echo "$ts_data" | awk '{print $2}')

            local latency=$(awk "BEGIN {print $snk_ts - $src_ts}")

            echo -e "${GREEN}✅ replicated in ${latency}s${NC}"
            return 0
        fi

        elapsed=$(($(date +%s) - start_time))
        if [ $elapsed -ge $timeout ]; then
            echo -e "${RED}❌ timed out after ${timeout}s${NC}"
            return 1
        fi
        sleep 1
    done
}

# Helper function to wait for a count to be reached in the sink
wait_for_replication() {
    local table="$1"
    local expected_count="$2"
    local description="$3"
    local timeout=${4:-60}
    local start_time=$(date +%s)

    echo -n "    ⏳ Waiting for the sink … "
    while true; do
        current_count=$(get_sink_count "$table" 2>/dev/null || echo "0")
        if [ "$current_count" == "$expected_count" ]; then
            local end_time=$(date +%s)
            local duration=$((end_time - start_time))
            echo -e "${GREEN}✅ replicated in ${duration}s${NC}"
            return 0
        fi

        elapsed=$(($(date +%s) - start_time))
        if [ $elapsed -ge $timeout ]; then
            echo -e "${RED}❌ timed out after ${timeout}s (expected ${expected_count}, got ${current_count})${NC}"
            return 1
        fi
        sleep 1
    done
}

# ─────────────────────────────────────────────────────────────────────────
# Connect-side helpers — used by use case 7, where the interesting outcome is
# NOT a row landing in the sink but a bad record being diverted to the DLQ
# while the connector stays alive. These read the Connect REST API (:8083) and
# count messages on a Kafka topic via a broker container.
# ─────────────────────────────────────────────────────────────────────────
CONNECT_URL="${CONNECT_URL:-http://localhost:8083}"

# Overall connector state (RUNNING / FAILED / ...).  $1 = connector name
get_connector_state() {
    local connector="$1"
    curl -s "$CONNECT_URL/connectors/$connector/status" 2>/dev/null \
        | jq -r '.connector.state // "UNKNOWN"' 2>/dev/null
}

# Number of tasks currently in FAILED state.  $1 = connector name
get_failed_task_count() {
    local connector="$1"
    curl -s "$CONNECT_URL/connectors/$connector/status" 2>/dev/null \
        | jq '[.tasks[]? | select(.state == "FAILED")] | length' 2>/dev/null || echo "0"
}

# Total messages on a topic (sum of end offsets across partitions).  $1 = topic
get_dlq_count() {
    local topic="$1"
    docker exec broker1 kafka-get-offsets --bootstrap-server broker1:29092 \
        --topic "$topic" 2>/dev/null | awk -F: '{sum += $3} END {print sum+0}'
}

# Wait until a topic reaches at least $2 messages, reporting the count.
#   $1 = topic   $2 = expected minimum   $3 = timeout (default 30)
wait_for_dlq() {
    local topic="$1"
    local expected="$2"
    local timeout=${3:-30}
    local start_time=$(date +%s)

    echo -n "    ⏳ Waiting for the DLQ … "
    while true; do
        local count=$(get_dlq_count "$topic")
        if [ "${count:-0}" -ge "$expected" ]; then
            echo -e "${GREEN}✅ ${count} record(s) in ${topic}${NC}"
            return 0
        fi

        elapsed=$(($(date +%s) - start_time))
        if [ $elapsed -ge $timeout ]; then
            echo -e "${RED}❌ timed out after ${timeout}s (expected ≥${expected}, got ${count:-0})${NC}"
            return 1
        fi
        sleep 1
    done
}

# Best-effort: print the error reason recorded in a DLQ record's headers.
# $1 = topic
show_dlq_error() {
    local topic="$1"
    docker exec broker1 kafka-console-consumer --bootstrap-server broker1:29092 \
        --topic "$topic" --from-beginning --max-messages 1 --timeout-ms 10000 \
        --property print.headers=true 2>/dev/null \
        | tr '\t' '\n' \
        | grep -a -o '__connect.errors.exception.message[^,]*' | head -1
}

# Helper function for high-precision delete timing on the sink
wait_for_sink_delete() {
    local table="$1"
    local expected_count="$2"
    local start_ts="$3" # The timestamp when the delete was initiated (date +%s.%N)
    local timeout=${4:-30}
    local start_wait=$(date +%s)

    echo -n "    ⏳ Waiting for the sink … "
    while true; do
        current_count=$(get_sink_count "$table" 2>/dev/null || echo "0")
        if [ "$current_count" == "$expected_count" ]; then
            local end_ts=$(date +%s.%N)
            local latency=$(awk "BEGIN {print $end_ts - $start_ts}")
            echo -e "${GREEN}✅ replicated in ${latency}s${NC}"
            return 0
        fi

        elapsed=$(($(date +%s) - start_wait))
        if [ $elapsed -ge $timeout ]; then
            echo -e "${RED}❌ timed out after ${timeout}s${NC}"
            return 1
        fi
        sleep 0.5
    done
}
