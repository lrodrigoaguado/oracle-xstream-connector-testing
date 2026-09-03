WHENEVER SQLERROR EXIT SQL.SQLCODE;

-- Sink-side schema for Oracle19 -> Oracle19 replication (runs in SINKPDB.DEMO).
-- Connect string used by 03_initialize_databases.sh:
--   demo/DemoPass123@//localhost:1521/SINKPDB
--
-- MIGRATION POLICY: the target schema is provisioned up front (the sink
-- connector runs with auto.create=false). Every table mirrors its source
-- table column-for-column, with these DELIBERATE differences:
--
--   1. LONG -> CLOB. Oracle SQL Language Reference: "Do not create tables
--      with LONG columns. Use LOB columns (CLOB, NCLOB, BLOB) instead. LONG
--      columns are supported only for backward compatibility." A migration is
--      the moment to leave LONG behind.
--   2. PRIMARY KEY added where the source is keyless (DEPARTMENTS, JOBS).
--      The sink upserts via MERGE keyed on the record key; without uniqueness
--      a duplicate would fail with ORA-30926. The target ends up BETTER
--      constrained than the source.
--   3. NOT NULL relaxed where Oracle's empty-string-IS-NULL collapse can
--      deliver NULL through JDBC (CLOB_TEST.CLOB_REQUIRED): EMPTY_CLOB()
--      arrives as NULL; a NOT NULL column would reject it with ORA-01400.
--   4. XMLTYPE/RAW travel as CLOB/VARCHAR2 shadow columns (XStream/Avro
--      transport) and are re-cast natively by the trigger below.
--   5. Every table carries three replication-metadata columns:
--      SOURCETIMESTAMP, SINKTIMESTAMP, MAQUINA_ID.

-- Drop existing tables for idempotency (children before parents for the FK).
BEGIN
   EXECUTE IMMEDIATE 'DROP TABLE ORDERS CASCADE CONSTRAINTS';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF;
END;
/
BEGIN
   EXECUTE IMMEDIATE 'DROP TABLE CUSTOMERS CASCADE CONSTRAINTS';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF;
END;
/
BEGIN
   EXECUTE IMMEDIATE 'DROP TABLE DATA_TYPES_TEST CASCADE CONSTRAINTS';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF;
END;
/
BEGIN
   EXECUTE IMMEDIATE 'DROP TABLE EMPLOYEES CASCADE CONSTRAINTS';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF;
END;
/
BEGIN
   EXECUTE IMMEDIATE 'DROP TABLE DEPARTMENTS CASCADE CONSTRAINTS';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF;
END;
/
BEGIN
   EXECUTE IMMEDIATE 'DROP TABLE JOBS CASCADE CONSTRAINTS';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF;
END;
/
BEGIN
   EXECUTE IMMEDIATE 'DROP TABLE AUDIT_LOG CASCADE CONSTRAINTS';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF;
END;
/
BEGIN
   EXECUTE IMMEDIATE 'DROP TABLE CLOB_TEST CASCADE CONSTRAINTS';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF;
END;
/

-- EMPLOYEES: exact mirror of the source + metadata columns.
-- PHONE_NUMBER is intentionally ABSENT: use case 1 adds it at the source
-- mid-demo and the sink connector's auto.evolve adds it here at runtime --
-- that moment demonstrates live schema evolution.
CREATE TABLE EMPLOYEES (
    EMPLOYEE_ID     NUMBER(6) PRIMARY KEY,
    FIRST_NAME      VARCHAR2(50),
    LAST_NAME       VARCHAR2(50),
    EMAIL           VARCHAR2(100),
    HIRE_DATE       DATE,
    SALARY          NUMBER(8,2),
    DEPARTMENT      VARCHAR2(50),
    SOURCETIMESTAMP TIMESTAMP,
    SINKTIMESTAMP   TIMESTAMP,
    MAQUINA_ID      VARCHAR2(50)
);

-- DEPARTMENTS: the source has NO primary key (only a unique index on
-- DEPT_ID). The target declares a real PK -- difference #2 above.
CREATE TABLE DEPARTMENTS (
    DEPT_ID         NUMBER(10) PRIMARY KEY,
    DEPT_NAME       VARCHAR2(50),
    LOCATION_ID     NUMBER(4),
    SOURCETIMESTAMP TIMESTAMP,
    SINKTIMESTAMP   TIMESTAMP,
    MAQUINA_ID      VARCHAR2(50)
);

-- JOBS: the source has neither PK nor unique index; the record key comes from
-- message.key.columns (JOB_ID). Same hardening as DEPARTMENTS.
CREATE TABLE JOBS (
    JOB_ID          VARCHAR2(10) PRIMARY KEY,
    JOB_TITLE       VARCHAR2(35),
    MIN_SALARY      NUMBER(6),
    MAX_SALARY      NUMBER(6),
    SOURCETIMESTAMP TIMESTAMP,
    SINKTIMESTAMP   TIMESTAMP,
    MAQUINA_ID      VARCHAR2(50)
);

-- AUDIT_LOG: unlike DEPARTMENTS/JOBS this table has NO candidate key at all, so
-- difference #2 (promote the key column to a PK) does NOT apply -- there is no
-- column to promote. It is pre-created only so the incident is reproduced
-- exactly as at the customer (same table on both sides); its records never
-- actually land here because the sink's Filter$Key SMT diverts every null-key
-- record to the DLQ (use case 7). The row count stays 0 by design.
CREATE TABLE AUDIT_LOG (
    CREATED_AT      VARCHAR2(30),
    ACTION          VARCHAR2(20),
    ENTITY          VARCHAR2(50),
    DETAILS         VARCHAR2(200),
    SOURCETIMESTAMP TIMESTAMP,
    SINKTIMESTAMP   TIMESTAMP,
    MAQUINA_ID      VARCHAR2(50)
);

-- CUSTOMERS (parent of ORDERS).
CREATE TABLE CUSTOMERS (
    CUSTOMER_ID     NUMBER(10) PRIMARY KEY,
    CUSTOMER_NAME   VARCHAR2(100) NOT NULL,
    EMAIL           VARCHAR2(100),
    SOURCETIMESTAMP TIMESTAMP,
    SINKTIMESTAMP   TIMESTAMP,
    MAQUINA_ID      VARCHAR2(50)
);

-- ORDERS (child) with deferrable FK so the JDBC sink's smart retries +
-- transaction-time validation can resolve out-of-order arrival.
CREATE TABLE ORDERS (
    ORDER_ID        NUMBER(10) PRIMARY KEY,
    ORDER_DATE      DATE DEFAULT SYSDATE,
    CUSTOMER_ID     NUMBER(10),
    TOTAL_AMOUNT    NUMBER(10, 2),
    SOURCETIMESTAMP TIMESTAMP,
    SINKTIMESTAMP   TIMESTAMP,
    MAQUINA_ID      VARCHAR2(50),
    CONSTRAINT FK_ORDERS_CUSTOMERS
        FOREIGN KEY (CUSTOMER_ID)
        REFERENCES CUSTOMERS (CUSTOMER_ID)
        DEFERRABLE INITIALLY DEFERRED
);

-- DATA_TYPES_TEST: mirror + difference #1 (LONG_COL -> CLOB) and #4 (the
-- XML/RAW shadow columns and back-cast trigger).
CREATE TABLE DATA_TYPES_TEST (
    ID              NUMBER(10) PRIMARY KEY,
    TEXT_COL        VARCHAR2(100),
    NUMBER_COL      NUMBER(10,2),
    DATE_COL        DATE,
    TIMESTAMP_COL   TIMESTAMP,
    CLOB_COL        CLOB,
    BLOB_COL        BLOB,
    LONG_COL        CLOB,
    XML_COL_CLOB    CLOB,
    XML_COL         XMLTYPE,
    RAW_COL         RAW(50),
    RAW_COL_VARCH   VARCHAR2(100),
    SOURCETIMESTAMP TIMESTAMP,
    SINKTIMESTAMP   TIMESTAMP,
    MAQUINA_ID      VARCHAR2(50)
)
XMLTYPE COLUMN XML_COL STORE AS CLOB;

CREATE OR REPLACE TRIGGER trg_sync_complex_types
BEFORE INSERT OR UPDATE ON DATA_TYPES_TEST
FOR EACH ROW
BEGIN
    IF :NEW.XML_COL_CLOB IS NOT NULL THEN
        :NEW.XML_COL := XMLTYPE(:NEW.XML_COL_CLOB);
    ELSE
        :NEW.XML_COL := NULL;
    END IF;

    IF :NEW.RAW_COL_VARCH IS NOT NULL THEN
        :NEW.RAW_COL := HEXTORAW(:NEW.RAW_COL_VARCH);
    ELSE
        :NEW.RAW_COL := NULL;
    END IF;
END;
/

-- CLOB_TEST: difference #3 -- CLOB_REQUIRED is NOT NULL at the source but
-- NULLABLE here. In Oracle an empty string IS NULL, so EMPTY_CLOB() arrives
-- through the JDBC sink as NULL; a NOT NULL column would reject those rows
-- with ORA-01400 and only non-empty rows would replicate.
CREATE TABLE CLOB_TEST (
    ID              NUMBER(10) PRIMARY KEY,
    DESCRIPTION     VARCHAR2(100),
    CLOB_NULLABLE   CLOB,
    CLOB_REQUIRED   CLOB,
    SOURCETIMESTAMP TIMESTAMP,
    SINKTIMESTAMP   TIMESTAMP,
    MAQUINA_ID      VARCHAR2(50)
);

EXIT;
