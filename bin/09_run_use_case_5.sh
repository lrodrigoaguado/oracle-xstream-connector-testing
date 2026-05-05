#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
USE_CASE_DIR="$PROJECT_DIR/sql/use_case_5"

# Source help functions
source "$SCRIPT_DIR/helpers.sh"

echo "------------------------------------------------------------------------"
echo "🧪 USE CASE 5: Referential Integrity (Smart Retries)"
echo "------------------------------------------------------------------------"
echo ""

# Ensure a clean start for the test records
echo "Cleaning up potential stale data from previous runs..."
docker exec -i oracle-xe sqlplus -S demo/DemoPass123@//localhost:1521/ORCLPDB1 <<SQL
DELETE FROM DEMO.ORDERS WHERE ORDER_ID IN (101, 102);
DELETE FROM DEMO.CUSTOMERS WHERE CUSTOMER_ID IN (1, 2);
COMMIT;
SQL

# Wait for cleanup to propagate to Postgres to have a clean initial count
wait_for_replication "ORDERS" "0" "cleanup of orders" 60
wait_for_replication "CUSTOMERS" "0" "cleanup of customers" 60

echo "ℹ️  This use case tests FK relationships between CUSTOMERS (parent) and ORDERS (child)."
echo "   The JDBC Sink uses Smart Retries to handle out-of-order arrival."
echo ""

# Get initial counts
CUST_INITIAL=$(get_postgres_count "CUSTOMERS" 2>/dev/null || echo "0")
ORD_INITIAL=$(get_postgres_count "ORDERS" 2>/dev/null || echo "0")

# Step 1: Operations (Inserts/Updates)
echo "------------------------------------------------------------------------"
echo "📝 Step 1: Testing INSERT/UPDATE operations with FK relationships"
echo "Inserting customers and orders with cross-references, and updating them in Oracle..."
run_oracle_sql "$USE_CASE_DIR/01_operations.sql"
echo "Oracle operations successful"

# 1. Update confirmation for Customer
wait_for_postgres_update "CUSTOMERS" "\"CUSTOMER_ID\" = 1" "John Updated" "CUSTOMER_NAME"

# 2. Update confirmation for Order
wait_for_postgres_update "ORDERS" "\"ORDER_ID\" = 101" "300.00" "TOTAL_AMOUNT"

# 3. Final counts
wait_for_replication "CUSTOMERS" "$((CUST_INITIAL + 2))" "2 new customers"
wait_for_replication "ORDERS" "$((ORD_INITIAL + 2))" "2 new orders" 90
echo ""

# Step 2: Delete
echo "------------------------------------------------------------------------"
echo "🗑️ Step 2: Testing DELETE with FK constraints"
echo "Removing order and customer records from the Oracle database..."
BEFORE_ORD_DELETE=$(get_postgres_count "ORDERS" 2>/dev/null || echo "0")
START_DELETE=$(date +%s.%N)
run_oracle_sql "$USE_CASE_DIR/02_deletes.sql"
echo "Oracle deletes successful"

# 1. Wait for Order Delete
EXPECTED_ORDERS=$((BEFORE_ORD_DELETE - 1))
wait_for_postgres_delete "ORDERS" "$EXPECTED_ORDERS" "$START_DELETE" 90

# 2. Wait for Customer Delete
wait_for_replication "CUSTOMERS" "$((CUST_INITIAL + 1))" "customer delete"
echo ""

echo "------------------------------------------------------------------------"
echo -e "${GREEN}✅ USE CASE 5 COMPLETED SUCCESSFULLY${NC}"
echo "------------------------------------------------------------------------"
