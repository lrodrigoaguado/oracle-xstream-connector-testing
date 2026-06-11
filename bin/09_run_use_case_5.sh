#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
USE_CASE_DIR="$PROJECT_DIR/sql/use_case_5"

source "$SCRIPT_DIR/helpers.sh"

uc_intro "5" "Foreign keys & out-of-order events" \
"CUSTOMERS (parent) and ORDERS (child) are linked by a deferrable FK. A child
  row is deliberately committed BEFORE its parent in one transaction; the JDBC
  sink's smart retries resolve the ordering without ever violating the FK."

# Preparation — clear test rows from any previous run
uc_step "Setup" "Clear test rows from any previous run"
docker exec -i oracle-19 sqlplus -S demo/DemoPass123@//localhost:1521/SOURCEPDB > /dev/null 2>&1 <<'SQL'
DELETE FROM DEMO.ORDERS WHERE ORDER_ID IN (101, 102);
DELETE FROM DEMO.CUSTOMERS WHERE CUSTOMER_ID IN (1, 2);
COMMIT;
SQL
wait_for_replication "ORDERS" "0" "cleanup of orders" 60
wait_for_replication "CUSTOMERS" "0" "cleanup of customers" 60
CUST_INITIAL=$(get_sink_count "CUSTOMERS" 2>/dev/null || echo "0")
ORD_INITIAL=$(get_sink_count "ORDERS" 2>/dev/null || echo "0")

# Step 1 — INSERT + UPDATE, including the out-of-order insert
uc_step "Step 1/2" "INSERT and UPDATE across the FK"
uc_source "INSERT customer 1, then order 101."
uc_source "UPDATE customer 1's name to 'John Updated'."
uc_source "UPDATE order 101's amount to 300.00."
uc_source "INSERT order 102 BEFORE its customer 2 (same transaction)."
run_oracle_sql "$USE_CASE_DIR/01_operations.sql"
wait_for_sink_update "CUSTOMERS" "\"CUSTOMER_ID\" = 1" "John Updated" "CUSTOMER_NAME"
wait_for_sink_update "ORDERS" "\"ORDER_ID\" = 101" "300.00" "TOTAL_AMOUNT"
wait_for_replication "CUSTOMERS" "$((CUST_INITIAL + 2))" "2 new customers"
wait_for_replication "ORDERS" "$((ORD_INITIAL + 2))" "2 new orders" 90
uc_note "Order 102 arrived before customer 2 — retries healed the ordering."

# Step 2 — DELETE in FK-safe order
uc_step "Step 2/2" "DELETE child then parent"
uc_source "Delete order 101, then customer 1."
BEFORE_ORD_DELETE=$(get_sink_count "ORDERS" 2>/dev/null || echo "0")
START_DELETE=$(date +%s.%N)
run_oracle_sql "$USE_CASE_DIR/02_deletes.sql"
wait_for_sink_delete "ORDERS" "$((BEFORE_ORD_DELETE - 1))" "$START_DELETE" 90
wait_for_replication "CUSTOMERS" "$((CUST_INITIAL + 1))" "customer delete"

uc_pass "5"
