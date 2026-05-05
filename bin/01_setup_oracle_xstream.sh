#!/bin/bash
#
# This script runs in two contexts:
#
#  1. Sourced by /opt/oracle/runUserScripts.sh during the Oracle 19c EE image's
#     first-time DB creation, because docker-compose mounts it at
#     /opt/oracle/scripts/setup/01_setup_xstream.sh. This is the primary path:
#     dbca has just created the CDB, the SPFILE it produced is in use, and
#     SHUTDOWN/STARTUP from inside this process tree work cleanly. Driving the
#     setup via `docker exec` after the container is "running" instead hits
#     ORA-32001 / ORA-00205 because the SPFILE chain is no longer canonical.
#
#  2. Executed manually via
#       docker exec oracle-xe bash /opt/oracle/scripts/setup/01_setup_xstream.sh
#     for re-runs / debugging. The wait-for-OPEN loop and the idempotency check
#     keep this safe.
#
# Everything runs inside a subshell so `set -e`, the ERR trap, and `exit` never
# leak into the parent shell. runUserScripts.sh sources us with `.`, and a
# leaked exit would terminate runOracle.sh and tear the container down.
(
    set -e

    # The Oracle 19c EE image only sets ORACLE_SID / ORACLE_PDB in
    # /home/oracle/.bashrc, which is not sourced by `docker exec`. Without
    # these, `sqlplus / as sysdba` fails with ORA-12162.
    export ORACLE_SID="${ORACLE_SID:-ORCLCDB}"
    export ORACLE_PDB="${ORACLE_PDB:-ORCLPDB1}"
    export ORAENV_ASK=NO

    log() {
        echo "================================================================================"
        echo ">> [XSTREAM SETUP] $1"
        echo "================================================================================"
    }

    # sqlplus exits 0 even when SQL statements fail. WHENEVER SQLERROR / OSERROR
    # EXIT FAILURE makes sqlplus surface ORA / OS errors via its exit code so
    # `set -e` and the ERR trap catch them.
    # NOTE: this does NOT catch errors from STARTUP / SHUTDOWN themselves
    # (SQL*Plus commands, not SQL); those are handled by the explicit
    # post-bounce status assertion below.
    sqlplus_sysdba() {
        {
            echo "WHENEVER SQLERROR EXIT FAILURE;"
            echo "WHENEVER OSERROR EXIT FAILURE;"
            echo "CONNECT / AS SYSDBA;"
            cat
            echo "EXIT;"
        } | sqlplus -S /nolog
    }

    trap '
        EXIT_CODE=$?
        echo "================================================================================"
        echo ">> [XSTREAM SETUP] FAILED (exit $EXIT_CODE) at line $LINENO."
        echo ">> Last 120 lines of the Oracle alert log to help diagnose the cause:"
        echo "================================================================================"
        ALERT_LOG=$(find /opt/oracle/diag/rdbms -name "alert_*.log" 2>/dev/null | head -1)
        if [ -n "$ALERT_LOG" ]; then
            tail -n 120 "$ALERT_LOG"
        else
            echo "(alert log not found under /opt/oracle/diag/rdbms)"
        fi
        exit $EXIT_CODE
    ' ERR

    is_setup_done() {
        local output
        output=$(sqlplus_sysdba 2>&1 <<SQL || echo FAILED
SET HEADING OFF
SET FEEDBACK OFF
SET PAGESIZE 0
SELECT count(*) FROM all_users WHERE username = 'C##CFLTUSER';
SQL
)
        [ "$(echo "$output" | tr -d ' \t\n\r')" = "1" ]
    }

    log "Checking if XStream is already configured..."

    # Wait until the CDB instance is OPEN.
    until sqlplus_sysdba >/dev/null 2>&1 <<-SQL
		SELECT 1 FROM v\$instance WHERE status = 'OPEN';
	SQL
    do
        log "Waiting for instance to be ready..."
        sleep 10
    done

    # Wait until the PDB is OPEN READ WRITE before issuing PDB-scoped statements.
    until sqlplus_sysdba >/dev/null 2>&1 <<-SQL
		SELECT 1 FROM v\$pdbs WHERE name = 'ORCLPDB1' AND open_mode = 'READ WRITE';
	SQL
    do
        log "Waiting for PDB ORCLPDB1 to be OPEN..."
        sleep 10
    done

    if is_setup_done; then
        log "XStream basic user setup already completed."
        # We continue to ensure Outbound Server is correctly configured.
    fi

    log "Starting XStream configuration..."

    log "Enable GoldenGate replication"
    sqlplus_sysdba <<SQL
ALTER SYSTEM SET enable_goldengate_replication=TRUE SCOPE=BOTH;
SQL

    log "Enable ARCHIVELOG mode (requires restart)"
    sqlplus_sysdba <<SQL
SHUTDOWN IMMEDIATE;
STARTUP MOUNT;
ALTER DATABASE ARCHIVELOG;
ALTER DATABASE OPEN;
ALTER PLUGGABLE DATABASE ALL OPEN;
SQL

    # STARTUP / SHUTDOWN do not honour WHENEVER SQLERROR. Confirm the bounce
    # actually left the database OPEN before continuing.
    log "Verifying instance is OPEN after bounce"
    sqlplus_sysdba <<SQL
DECLARE v VARCHAR2(20); BEGIN
  SELECT status INTO v FROM v\$instance;
  IF v <> 'OPEN' THEN
    RAISE_APPLICATION_ERROR(-20001, 'Instance not OPEN after bounce: '||v);
  END IF;
END;
/
SQL

    log "Enable Supplemental Logging"
    sqlplus_sysdba <<SQL
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
SQL

    log "Create XStream user (C##CFLTUSER)"
    sqlplus_sysdba <<SQL
CREATE USER c##cfltuser IDENTIFIED BY My_RandomPass192837465 DEFAULT TABLESPACE USERS QUOTA UNLIMITED ON USERS CONTAINER=ALL;
GRANT CREATE SESSION, SET CONTAINER, SELECT_CATALOG_ROLE TO c##cfltuser CONTAINER=ALL;
GRANT SELECT ANY TABLE, FLASHBACK ANY TABLE, LOCK ANY TABLE TO c##cfltuser CONTAINER=ALL;
SQL

    log "Create Demo user (DEMO)"
    sqlplus_sysdba <<SQL
ALTER SESSION SET CONTAINER = ORCLPDB1;
CREATE USER demo IDENTIFIED BY DemoPass123 DEFAULT TABLESPACE USERS QUOTA UNLIMITED ON USERS;
GRANT CREATE SESSION, CREATE TABLE, CREATE SEQUENCE, CREATE TRIGGER TO demo;
SQL

    log "Grant XStream Admin Privileges"
    sqlplus_sysdba <<SQL
BEGIN
  DBMS_XSTREAM_AUTH.GRANT_ADMIN_PRIVILEGE(
    grantee => 'c##cfltuser',
    privilege_type => 'CAPTURE',
    grant_select_privileges => TRUE,
    container => 'ALL'
  );

  EXECUTE IMMEDIATE 'GRANT SELECT ON DBA_INDEXES TO c##cfltuser CONTAINER=ALL';
  EXECUTE IMMEDIATE 'GRANT SELECT ON DBA_IND_COLUMNS TO c##cfltuser CONTAINER=ALL';
END;
/
SQL

    log "Grant PDB-level privileges for index detection"
    sqlplus_sysdba <<SQL
ALTER SESSION SET CONTAINER = ORCLPDB1;
GRANT SELECT ON SYS.DBA_INDEXES TO c##cfltuser;
GRANT SELECT ON SYS.DBA_IND_COLUMNS TO c##cfltuser;
GRANT SELECT ON SYS.ALL_INDEXES TO c##cfltuser;
GRANT SELECT ON SYS.ALL_IND_COLUMNS TO c##cfltuser;
SQL

    log "Create Outbound Server"
    sqlplus_sysdba <<SQL
DECLARE
  tables DBMS_UTILITY.UNCL_ARRAY;
  schemas DBMS_UTILITY.UNCL_ARRAY;
BEGIN
  tables(1) := 'DEMO.EMPLOYEES';
  tables(2) := 'DEMO.DATA_TYPES_TEST';
  tables(3) := 'DEMO.DEPARTMENTS';
  tables(4) := 'DEMO.JOBS';
  tables(5) := 'DEMO.CUSTOMERS';
  tables(6) := 'DEMO.ORDERS';
  tables(7) := NULL;
  schemas(1) := 'DEMO';
  schemas(2) := NULL;

  DBMS_XSTREAM_ADM.CREATE_OUTBOUND(
    capture_name          =>  'CONFLUENT_XOUT1',
    server_name           =>  'XOUT',
    source_container_name =>  'ORCLPDB1',
    table_names           =>  tables,
    schema_names          =>  schemas,
    comment               => 'Confluent XStream CDC Connector' );

  DBMS_CAPTURE_ADM.ALTER_CAPTURE(
    capture_name => 'CONFLUENT_XOUT1',
    checkpoint_retention_time => 1);

  DBMS_XSTREAM_ADM.SET_PARAMETER(
    streams_type => 'capture',
    streams_name => 'CONFLUENT_XOUT1',
    parameter    => 'max_sga_size',
    value        => '256');

  DBMS_XSTREAM_ADM.SET_PARAMETER(
    streams_type => 'apply',
    streams_name => 'XOUT',
    parameter    => 'max_sga_size',
    value        => '256');
END;
/
EXEC DBMS_XSTREAM_ADM.ALTER_OUTBOUND(server_name=>'XOUT', connect_user=>'c##cfltuser');
SQL

    log "XStream setup completed successfully."
)
RC=$?
if [ "$RC" -ne 0 ]; then
    echo ">> [XSTREAM SETUP] Subshell exited with code $RC. The Oracle container will continue, but XStream is NOT configured."
fi
