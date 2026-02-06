#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
USE_CASE_DIR="$PROJECT_DIR/sql/use_case_4"

# Source help functions
source "$SCRIPT_DIR/helpers.sh"

echo "------------------------------------------------------------------------"
echo "🧪 USE CASE 4: CLOB Replication (NULL vs EMPTY)"
echo "------------------------------------------------------------------------"
echo ""

# Ensure a clean start
echo "Cleaning up potential stale data..."
docker exec -i oracle-xe sqlplus -S demo/DemoPass123@//localhost:1521/XEPDB1 <<SQL
BEGIN
   EXECUTE IMMEDIATE 'DROP TABLE DEMO.CLOB_TEST';
EXCEPTION
   WHEN OTHERS THEN
      IF SQLCODE != -942 THEN
         RAISE;
      END IF;
END;
/
COMMIT;
SQL

# Wait for cleanup (Postgres table might be dropped by connector if auto-evolve handles drops, but usually we just want to ensure Oracle is clean)
# We will just proceed to create table.

# Step 1: Create Table
echo "------------------------------------------------------------------------"
echo "📝 Step 1: Creating Table"
run_oracle_sql "$USE_CASE_DIR/01_create_tables.sql"
echo "Table created."
sleep 5

echo "🛠️ Manually creating Postgres table to ensure consistency..."
docker exec -i postgres psql -U test-connector -d test-connector <<EOF
DROP TABLE IF EXISTS "CLOB_TEST";
CREATE TABLE IF NOT EXISTS "CLOB_TEST" (
    "ID" DOUBLE PRECISION PRIMARY KEY,
    "DESCRIPTION" TEXT,
    "CLOB_NULLABLE" TEXT,
    "CLOB_REQUIRED" TEXT NOT NULL DEFAULT '',
    "MAQUINA_ID" TEXT,
    "SOURCETIMESTAMP" TIMESTAMP,
    "SINKTIMESTAMP" TIMESTAMP
);
EOF


# Step 2: Inserts
echo "------------------------------------------------------------------------"
echo "📝 Step 2: Testing INSERT operations"
run_oracle_sql "$USE_CASE_DIR/02_inserts.sql"
echo "Oracle inserts successful."

echo "⏳ Waiting for replication..."
wait_for_replication "CLOB_TEST" "3" "initial inserts"

echo "🔍 Verifying Insert Results..."

# Check ID 1 (Normal Nullable, Empty Required)
ID1_NULLABLE=$(get_postgres_value "CLOB_TEST" "\"ID\" = 1" "CLOB_NULLABLE")
ID1_REQUIRED=$(get_postgres_value "CLOB_TEST" "\"ID\" = 1" "CLOB_REQUIRED")
echo "ID 1 - Nullable: '$ID1_NULLABLE', Required: '$ID1_REQUIRED'"

if [[ "$ID1_NULLABLE" == "This is a nullable CLOB" && "$ID1_REQUIRED" == "" ]]; then
    echo -e "${GREEN}✅ ID 1 Correct (Nullable populated, Required empty)${NC}"
else
    echo -e "${RED}❌ ID 1 Incorrect${NC}"
fi

# Check ID 2 (NULL Nullable, Populated Required)
ID2_NULLABLE=$(get_postgres_value "CLOB_TEST" "\"ID\" = 2" "CLOB_NULLABLE")
ID2_REQUIRED=$(get_postgres_value "CLOB_TEST" "\"ID\" = 2" "CLOB_REQUIRED")
echo "ID 2 - Nullable: '$ID2_NULLABLE', Required: '$ID2_REQUIRED'"

if [[ (-z "$ID2_NULLABLE" || "$ID2_NULLABLE" == "null") && "$ID2_REQUIRED" == "Required CLOB cannot be null" ]]; then
     echo -e "${GREEN}✅ ID 2 Correct (Nullable NULL, Required populated)${NC}"
else
     echo -e "${RED}❌ ID 2 Incorrect${NC}"
fi

# Check ID 3 (NULL Nullable, Empty Required)
ID3_NULLABLE=$(get_postgres_value "CLOB_TEST" "\"ID\" = 3" "CLOB_NULLABLE")
ID3_REQUIRED=$(get_postgres_value "CLOB_TEST" "\"ID\" = 3" "CLOB_REQUIRED")
echo "ID 3 - Nullable: '$ID3_NULLABLE', Required: '$ID3_REQUIRED'"

if [[ "$ID3_REQUIRED" == "" ]]; then
    echo -e "${GREEN}✅ ID 3 Required is Empty String (Preserved EMPTY_CLOB)${NC}"
else
    echo -e "${RED}❌ ID 3 Required should be Empty String, got '$ID3_REQUIRED'${NC}"
fi


# Step 3: Updates
echo "------------------------------------------------------------------------"
echo "📝 Step 3: Testing UPDATE operations"
run_oracle_sql "$USE_CASE_DIR/03_updates.sql"
echo "Oracle updates successful."

echo "⏳ Waiting for update propagation..."
# Wait for ID 2 update (Nullable -> Value)
wait_for_postgres_update "CLOB_TEST" "\"ID\" = 2" "Updated to a value" "CLOB_NULLABLE"
# Wait for ID 1 update (Required -> Value)
wait_for_postgres_update "CLOB_TEST" "\"ID\" = 1" "Updated Required" "CLOB_REQUIRED"

echo "🔍 Verifying Update Results..."

# Check ID 1 Updates:
# Nullable: Value -> NULL
# Required: Empty -> Value
ID1_NULLABLE_NEW=$(get_postgres_value "CLOB_TEST" "\"ID\" = 1" "CLOB_NULLABLE")
ID1_REQUIRED_NEW=$(get_postgres_value "CLOB_TEST" "\"ID\" = 1" "CLOB_REQUIRED")
echo "ID 1 New - Nullable: '$ID1_NULLABLE_NEW', Required: '$ID1_REQUIRED_NEW'"

if [[ -z "$ID1_NULLABLE_NEW" ]]; then
     echo -e "${GREEN}✅ ID 1 Nullable updated to NULL${NC}"
else
     echo -e "${RED}❌ ID 1 Nullable failed update${NC}"
fi

if [[ "$ID1_REQUIRED_NEW" == "Updated Required" ]]; then
     echo -e "${GREEN}✅ ID 1 Required updated to Value${NC}"
else
     echo -e "${RED}❌ ID 1 Required failed update to Value${NC}"
fi

# Check ID 2 Updates:
# Nullable: NULL -> Value
# Required: Value -> Empty
ID2_NULLABLE_NEW=$(get_postgres_value "CLOB_TEST" "\"ID\" = 2" "CLOB_NULLABLE")
ID2_REQUIRED_NEW=$(get_postgres_value "CLOB_TEST" "\"ID\" = 2" "CLOB_REQUIRED")

if [[ "$ID2_NULLABLE_NEW" == "Updated to a value" ]]; then
     echo -e "${GREEN}✅ ID 2 Nullable updated to Value${NC}"
else
     echo -e "${RED}❌ ID 2 Nullable failed update${NC}"
fi

if [[ "$ID2_REQUIRED_NEW" == "" ]]; then
     echo -e "${GREEN}✅ ID 2 Required updated to Empty String${NC}"
else
     echo -e "${RED}❌ ID 2 Required failed update to Empty String${NC}"
fi

# Check ID 3 Update (Non-CLOB update, CLOB preserved)
ID3_DESCR_NEW=$(get_postgres_value "CLOB_TEST" "\"ID\" = 3" "DESCRIPTION")
if [[ "$ID3_DESCR_NEW" == "Updated Description" ]]; then
     echo -e "${GREEN}✅ ID 3 Check non-CLOB update${NC}"
else
     echo -e "${RED}❌ ID 3 Failed non-CLOB update${NC}"
fi

echo "------------------------------------------------------------------------"
echo -e "${GREEN}✅ USE CASE 4 COMPLETED${NC}"
echo "------------------------------------------------------------------------"
