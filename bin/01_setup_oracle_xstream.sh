#!/bin/bash
set -e

log() {
    echo "================================================================================"
    echo ">> [XSTREAM SETUP] $1"
    echo "================================================================================"
}

# Function to check if setup is already done
is_setup_done() {
    # Check if C##CFLTUSER exists
    count=$(echo "SELECT count(*) FROM all_users WHERE username = 'C##CFLTUSER';" | sqlplus -S / as sysdba | grep -E '[0-9]+' | tr -d ' \t')
    if [ "$count" -eq "1" ]; then
        return 0
    else
        return 1
    fi
}

log "Checking if XStream is already configured..."

# Wait for database to be open before checking (optional, but good practice if called early)
until echo "select 1 from dual;" | sqlplus -S / as sysdba >/dev/null 2>&1; do
    log "Waiting for instance to be ready..."
    sleep 5
done

if is_setup_done; then
    log "XStream setup already completed."
    log "Ensuring XStream Outbound Server is started..."
    sqlplus -S / as sysdba <<SQL
BEGIN
  DBMS_XSTREAM_ADM.START_OUTBOUND(server_name => 'XOUT');
EXCEPTION
  WHEN OTHERS THEN
    NULL; -- Ignore if already running or other minor errors
END;
/
EXIT;
SQL
    exit 0
fi

log "Starting XStream configuration..."

log "Enable GoldenGate replication"
sqlplus -S / as sysdba <<SQL
ALTER SYSTEM SET enable_goldengate_replication=TRUE SCOPE=BOTH;
EXIT;
SQL

log "Enable ARCHIVELOG mode (requires restart)"
# This sequence shuts down and restarts the database instance
sqlplus -S / as sysdba <<SQL
SHUTDOWN IMMEDIATE;
STARTUP MOUNT;
ALTER DATABASE ARCHIVELOG;
ALTER DATABASE OPEN;
EXIT;
SQL

log "Enable Supplemental Logging"
sqlplus -S / as sysdba <<SQL
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
EXIT;
SQL

log "Create XStream user (C##CFLTUSER)"
sqlplus -S / as sysdba <<SQL
CREATE USER c##cfltuser IDENTIFIED BY My_RandomPass192837465 DEFAULT TABLESPACE USERS QUOTA UNLIMITED ON USERS CONTAINER=ALL;
GRANT CREATE SESSION, SET CONTAINER, SELECT_CATALOG_ROLE TO c##cfltuser CONTAINER=ALL;
GRANT SELECT ANY TABLE, FLASHBACK ANY TABLE, LOCK ANY TABLE TO c##cfltuser CONTAINER=ALL;
EXIT;
SQL

log "Create Demo user (DEMO)"
sqlplus -S / as sysdba <<SQL
ALTER SESSION SET CONTAINER = XEPDB1;
CREATE USER demo IDENTIFIED BY DemoPass123 DEFAULT TABLESPACE USERS QUOTA UNLIMITED ON USERS;
GRANT CREATE SESSION, CREATE TABLE, CREATE SEQUENCE, CREATE TRIGGER TO demo;
EXIT;
SQL

log "Grant XStream Admin Privileges"
sqlplus -S / as sysdba <<SQL
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
EXIT;
SQL

log "Grant PDB-level privileges for index detection"
sqlplus -S / as sysdba <<SQL
ALTER SESSION SET CONTAINER = XEPDB1;
GRANT SELECT ON SYS.DBA_INDEXES TO c##cfltuser;
GRANT SELECT ON SYS.DBA_IND_COLUMNS TO c##cfltuser;
GRANT SELECT ON SYS.ALL_INDEXES TO c##cfltuser;
GRANT SELECT ON SYS.ALL_IND_COLUMNS TO c##cfltuser;
EXIT;
SQL

log "Create Outbound Server"
sqlplus -S / as sysdba <<SQL
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
    source_container_name =>  'XEPDB1',
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
EXIT;
SQL

log "XStream setup completed successfully."
