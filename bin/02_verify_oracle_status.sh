#!/bin/bash

# Define colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "🔍 Verifying Oracle XStream Configuration..."

# 1. Check Outbound Server Status
echo "----------------------------------------"
echo "Checking XStream Outbound Server Status:"
OUTBOUND_OUTPUT=$(docker exec -i -e ORACLE_SID=ORCLCDB oracle-19 sqlplus -S / as sysdba <<SQL
SET LINESIZE 200
SET PAGESIZE 100
COL server_name FORMAT a20
COL status FORMAT a15
SELECT server_name, status FROM dba_xstream_outbound;
EXIT;
SQL
)
echo "$OUTBOUND_OUTPUT"

SERVER_STATUS=$(echo "$OUTBOUND_OUTPUT" | grep -E "^XOUT" | awk '{print $2}')

# 2. Check Capture Process Status
echo "----------------------------------------"
echo "Checking Capture Process Status:"
CAPTURE_OUTPUT=$(docker exec -i -e ORACLE_SID=ORCLCDB oracle-19 sqlplus -S / as sysdba <<SQL
SET LINESIZE 200
SET PAGESIZE 100
COL capture_name FORMAT a20
COL queue_name FORMAT a20
COL status FORMAT a15
COL error_message FORMAT a60
SELECT capture_name, queue_name, status, error_message FROM dba_capture;
EXIT;
SQL
)
echo "$CAPTURE_OUTPUT"

CAPTURE_STATUS=$(echo "$CAPTURE_OUTPUT" | grep -E "^CONFLUENT" | awk '{print $3}')

# 3. Check User
echo "----------------------------------------"
echo "Checking Connector User (C##CFLTUSER):"
docker exec -i -e ORACLE_SID=ORCLCDB oracle-19 sqlplus -S / as sysdba <<SQL
SET LINESIZE 200
COL username FORMAT a20
COL account_status FORMAT a20
SELECT username, account_status FROM dba_users WHERE username = 'C##CFLTUSER';
EXIT;
SQL

echo "----------------------------------------"

# Interpreting Results
IS_READY=true

if [ -z "$SERVER_STATUS" ]; then
    echo -e "${RED}❌ XStream Outbound Server NOT FOUND.${NC}"
    IS_READY=false
elif [[ "$SERVER_STATUS" == "DISABLED" || "$SERVER_STATUS" == "ABORTED" ]]; then
    echo -e "${RED}❌ XStream Outbound Server is $SERVER_STATUS (Expected: DETACHED or ATTACHED).${NC}"
    IS_READY=false
else
    echo -e "${GREEN}✅ XStream Outbound Server is $SERVER_STATUS.${NC}"
fi

if [ -z "$CAPTURE_STATUS" ]; then
    echo -e "${RED}❌ Capture Process NOT FOUND.${NC}"
    IS_READY=false
elif [[ "$CAPTURE_STATUS" == "DISABLED" || "$CAPTURE_STATUS" == "ABORTED" ]]; then
    echo -e "${RED}❌ Capture Process is $CAPTURE_STATUS (Expected: ENABLED or CAPTURING).${NC}"
    IS_READY=false
else
    echo -e "${GREEN}✅ Capture Process is $CAPTURE_STATUS.${NC}"
fi

echo "----------------------------------------"
if [ "$IS_READY" = true ]; then
    echo -e "${GREEN}✅ SYSTEM IS READY FOR DEMO.${NC}"
    echo "You can now run ./bin/03_initialize_databases.sh followed by ./bin/04_deploy_connectors.sh"
else
    echo -e "${RED}⚠️ SYSTEM IS NOT READY.${NC}"
    echo "Please check logs or restart the setup explicitly."
    echo "----------------------------------------"
    echo "Last 20 lines of Oracle Alert Log:"
    docker exec oracle-19 tail -n 20 /opt/oracle/diag/rdbms/orclcdb/ORCLCDB/trace/alert_ORCLCDB.log
fi
