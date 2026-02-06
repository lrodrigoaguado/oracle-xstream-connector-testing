#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
USE_CASE_DIR="$PROJECT_DIR/sql/use_case_6"
# Use the unified connector configurations
SOURCE_CONFIG="$PROJECT_DIR/etc/connectors/source-connector.json"
SINK_CONFIG="$PROJECT_DIR/etc/connectors/sink-connector.json"
CONNECT_URL="http://localhost:8083"

# Source help functions
source "$SCRIPT_DIR/helpers.sh"

echo "------------------------------------------------------------------------"
echo "🧪 USE CASE 6: Partial LOB Update (Custom SMT Test)"
echo "------------------------------------------------------------------------"
echo ""

# Reset Postgres state to ensure we are testing preservation
echo "🧹 Resetting CLOB_COL for ID=2 in Postgres to a known state..."
docker exec -i postgres psql -U test-connector -d test-connector -c "UPDATE \"DEMO.DATA_TYPES_TEST\" SET \"CLOB_COL\" = 'Initial baseline content' WHERE \"ID\" = 2;" > /dev/null

# Initial check
echo "📊 Current CLOB_COL for ID=2 in Postgres (Baseline):"
get_postgres_value "DEMO.DATA_TYPES_TEST" "\"ID\" = 2" "CLOB_COL"
echo ""

# Step 1: Update
echo "------------------------------------------------------------------------"
echo "📝 Step 1: Testing PARTIAL UPDATE operation"
echo "Updating NUMBER_COL for ID 2 in Oracle. CLOB_COL should remain unchanged."
run_oracle_sql "$USE_CASE_DIR/01_partial_update.sql"

echo "⏳ Waiting for update propagation..."
wait_for_postgres_update "DEMO.DATA_TYPES_TEST" "\"ID\" = 2" "99999.99" "NUMBER_COL"

echo "🔍 Verifying CLOB_COL content..."
CLOB_CONTENT=$(get_postgres_value "DEMO.DATA_TYPES_TEST" "\"ID\" = 2" "CLOB_COL")
echo "CLOB Content: $CLOB_CONTENT"

if [[ "$CLOB_CONTENT" == "Initial baseline content" ]]; then
    echo -e "${GREEN}✅ SUCCESS: CLOB content preserved!${NC}"
else
    echo -e "${RED}❌ FAILURE: CLOB content unexpected: $CLOB_CONTENT${NC}"
    # Check if we see the placeholder
    if [[ "$CLOB_CONTENT" == "__cflt_unavailable_value" ]]; then
        echo -e "${RED}❌ FAILURE: Placeholder found! SMT did not remove it.${NC}"
    fi
fi

echo "------------------------------------------------------------------------"
echo -e "${GREEN}✅ USE CASE 6 COMPLETED${NC}"
echo "------------------------------------------------------------------------"
