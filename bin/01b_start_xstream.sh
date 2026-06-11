#!/bin/bash
#
# XStream capture + outbound-server STARTUP hook.
#
# Why this exists (and is separate from 01_setup_oracle_xstream.sh):
#
#   01_setup_oracle_xstream.sh runs from /opt/oracle/scripts/setup/ during the
#   19c EE image's first-time DB creation. DBMS_XSTREAM_ADM.CREATE_OUTBOUND there
#   creates AND starts the capture + outbound server -- but in that *initial*
#   instance incarnation. The image then performs a final handover restart to
#   launch the long-running container instance, and the capture/apply do NOT
#   auto-resume across that restart: they land DISABLED with no error. Starting
#   them at the end of setup would not help, because the same final restart would
#   disable them again.
#
#   This script is mounted into /opt/oracle/scripts/startup/ instead. The image
#   sources scripts/startup on EVERY container boot, AFTER the final instance is
#   open. So it (re)starts the capture + outbound server in the correct -- final --
#   incarnation, both on the first boot after creation and on every later
#   `docker compose up`. It is idempotent: it only starts a process that is not
#   already ENABLED, and does nothing if the XStream objects don't exist yet.
#
# Everything runs inside a subshell so `set -e`, the ERR trap, and `exit` never
# leak into the parent shell. runUserScripts.sh sources us with `.`, and a leaked
# exit would terminate runOracle.sh and tear the container down.
(
    set -e

    # The 19c EE image only sets ORACLE_SID / ORACLE_PDB in /home/oracle/.bashrc,
    # which is not sourced by `docker exec`. Without these, `sqlplus / as sysdba`
    # fails with ORA-12162.
    export ORACLE_SID="${ORACLE_SID:-ORCLCDB}"
    export ORACLE_PDB="${ORACLE_PDB:-SOURCEPDB}"
    export ORAENV_ASK=NO

    log() {
        echo "================================================================================"
        echo ">> [XSTREAM STARTUP] $1"
        echo "================================================================================"
    }

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
        echo ">> [XSTREAM STARTUP] FAILED (exit $EXIT_CODE) at line $LINENO."
        echo "================================================================================"
        exit $EXIT_CODE
    ' ERR

    log "Waiting for instance + SOURCEPDB to be OPEN before starting XStream processes..."

    # Wait until the CDB instance is OPEN.
    until sqlplus_sysdba >/dev/null 2>&1 <<-SQL
		SELECT 1 FROM v\$instance WHERE status = 'OPEN';
	SQL
    do
        sleep 5
    done

    # Wait until SOURCEPDB is OPEN READ WRITE (the capture's source container).
    until sqlplus_sysdba >/dev/null 2>&1 <<-SQL
		SELECT 1 FROM v\$pdbs WHERE name = 'SOURCEPDB' AND open_mode = 'READ WRITE';
	SQL
    do
        sleep 5
    done

    # If the outbound server was never created (e.g. setup has not run yet, or
    # failed), there is nothing to start. Bail out quietly. NOTE: a SELECT that
    # returns zero rows still exits 0, so we must count rows rather than rely on
    # the exit code of a bare SELECT.
    OUTBOUND_COUNT=$(sqlplus_sysdba <<-SQL | tr -d ' \t\n\r'
		SET HEADING OFF FEEDBACK OFF PAGESIZE 0;
		SELECT COUNT(*) FROM dba_xstream_outbound WHERE server_name = 'XOUT';
	SQL
)
    if [ "$OUTBOUND_COUNT" != "1" ]; then
        log "Outbound server XOUT not found - nothing to start. Skipping."
    else
        # Start the outbound server (apply) first, then the capture. Both starts
        # are conditional on the process not already being ENABLED, so this hook
        # is safe to run on every boot.
        log "Ensuring outbound server XOUT and capture CONFLUENT_XOUT1 are running"
        sqlplus_sysdba <<SQL
DECLARE
  v_status VARCHAR2(30);
BEGIN
  SELECT status INTO v_status FROM dba_apply WHERE apply_name = 'XOUT';
  IF v_status <> 'ENABLED' THEN
    DBMS_APPLY_ADM.START_APPLY(apply_name => 'XOUT');
  END IF;
EXCEPTION
  WHEN NO_DATA_FOUND THEN NULL;
END;
/
DECLARE
  v_status VARCHAR2(30);
BEGIN
  SELECT status INTO v_status FROM dba_capture WHERE capture_name = 'CONFLUENT_XOUT1';
  IF v_status <> 'ENABLED' THEN
    DBMS_CAPTURE_ADM.START_CAPTURE(capture_name => 'CONFLUENT_XOUT1');
  END IF;
EXCEPTION
  WHEN NO_DATA_FOUND THEN NULL;
END;
/
SQL
        log "XStream capture + outbound server are started."
    fi
)
RC=$?
if [ "$RC" -ne 0 ]; then
    echo ">> [XSTREAM STARTUP] Subshell exited with code $RC. XStream capture/outbound server may NOT be running."
fi
