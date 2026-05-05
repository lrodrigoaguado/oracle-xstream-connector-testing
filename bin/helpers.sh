#!/bin/bash

# Shared colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Helper function to run Oracle SQL (silently by default)
run_oracle_sql() {
    local sql_file="$1"
    local silent="${2:-true}"

    if [ "$silent" == "true" ]; then
        cat "$sql_file" | docker exec -i oracle-xe sqlplus -S demo/DemoPass123@//localhost:1521/ORCLPDB1 > /dev/null 2>&1
    else
        echo -e "${YELLOW}📤 Executing: $(basename "$sql_file")${NC}"
        cat "$sql_file" | docker exec -i oracle-xe sqlplus -S demo/DemoPass123@//localhost:1521/ORCLPDB1
    fi
}

# Helper function to get Postgres row count
get_postgres_count() {
    local table="$1"
    local count=$(docker exec -i postgres psql -U test-connector -d test-connector -t -c "SELECT COUNT(*) FROM \"$table\";" 2>/dev/null | xargs)
    echo "${count:-0}"
}

# Helper function to get value from Postgres
get_postgres_value() {
    local table="$1"
    local condition="$2"
    local column="$3"
    # Use xargs to trim leading/trailing whitespace without stripping internal spaces
    docker exec -i postgres psql -U test-connector -d test-connector -t -c "SELECT \"$column\" FROM \"$table\" WHERE $condition;" 2>/dev/null | xargs
}

# Helper function to calculate latency for UPDATE
wait_for_postgres_update() {
    local table=$1
    local condition=$2
    local expected_val=$3
    local check_column=$4
    local timeout=${5:-30}
    local start_time=$(date +%s)

    echo -n "⏳ Waiting for update in $table ($condition)..."
    while true; do
        current_val=$(get_postgres_value "$table" "$condition" "$check_column")
        if [ "$current_val" == "$expected_val" ]; then
            # Get timestamps for latency calculation
            local ts_data=$(docker exec -i postgres psql -U test-connector -d test-connector -t -c \
                "SELECT extract(epoch from \"SOURCETIMESTAMP\"), extract(epoch from \"SINKTIMESTAMP\") FROM \"$table\" WHERE $condition;" 2>/dev/null)

            # Simple parsing of extracted epochs
            local src_ts=$(echo $ts_data | awk '{print $1}')
            local snk_ts=$(echo $ts_data | awk '{print $3}')

            # Use awk for precision subtraction
            local latency=$(awk "BEGIN {print $snk_ts - $src_ts}")

            echo -e "\n${GREEN}✅ Replicated in Postgres in ${latency}s${NC}"
            return 0
        fi

        elapsed=$(($(date +%s) - start_time))
        if [ $elapsed -ge $timeout ]; then
            echo -e "\n${RED}❌ Timeout after ${timeout}s${NC}"
            return 1
        fi
        sleep 1
    done
}

# Helper function to wait for replication (count based)
wait_for_replication() {
    local table="$1"
    local expected_count="$2"
    local description="$3"
    local timeout=${4:-60}
    local start_time=$(date +%s)

    echo -n "⏳ Waiting for $description in $table..."
    while true; do
        current_count=$(get_postgres_count "$table" 2>/dev/null || echo "0")
        if [ "$current_count" == "$expected_count" ]; then
            local end_time=$(date +%s)
            local duration=$((end_time - start_time))
            echo -e "\n${GREEN}✅ Replicated in Postgres in ${duration}s${NC}"
            return 0
        fi

        elapsed=$(($(date +%s) - start_time))
        if [ $elapsed -ge $timeout ]; then
            echo -e "\n${RED}❌ Timeout after ${timeout}s (expected: $expected_count, got: $current_count)${NC}"
            return 1
        fi
        sleep 1
    done
}

# Helper function for high-precision delete timing
wait_for_postgres_delete() {
    local table="$1"
    local expected_count="$2"
    local start_ts="$3" # The timestamp when the delete was initiated (date +%s.%N)
    local timeout=${4:-30}
    local start_wait=$(date +%s)

    echo -n "⏳ Waiting for delete in $table..."
    while true; do
        current_count=$(get_postgres_count "$table" 2>/dev/null || echo "0")
        if [ "$current_count" == "$expected_count" ]; then
            local end_ts=$(date +%s.%N)
            local latency=$(awk "BEGIN {print $end_ts - $start_ts}")
            echo -e "\n${GREEN}✅ Replicated in Postgres in ${latency}s${NC}"
            return 0
        fi

        elapsed=$(($(date +%s) - start_wait))
        if [ $elapsed -ge $timeout ]; then
            echo -e "\n${RED}❌ Timeout after ${timeout}s${NC}"
            return 1
        fi
        sleep 0.5
    done
}
