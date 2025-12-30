-- Create table with various data types
CREATE TABLE C##CFLTUSER.DATA_TYPES_TEST (
    ID NUMBER PRIMARY KEY,
    TEXT_COL VARCHAR2(100),
    NUMBER_COL NUMBER(10,2),
    DATE_COL DATE,
    TIMESTAMP_COL TIMESTAMP,
    CLOB_COL CLOB,
    BLOB_COL BLOB,
    XML_COL XMLTYPE,
    LONG_COL LONG,
    XML_COL_CLOB CLOB
) XMLTYPE COLUMN XML_COL STORE AS CLOB;

-- Create trigger to auto-convert XMLTYPE to CLOB for capture
CREATE OR REPLACE TRIGGER C##CFLTUSER.trg_data_types_test
BEFORE INSERT OR UPDATE ON C##CFLTUSER.DATA_TYPES_TEST
FOR EACH ROW
BEGIN
    -- Handle XMLTYPE -> CLOB
    -- Use UPDATING predicate to avoid complex XMLTYPE comparison or unsupported syntax
    IF INSERTING OR UPDATING('XML_COL') THEN
        IF :NEW.XML_COL IS NOT NULL THEN
            :NEW.XML_COL_CLOB := :NEW.XML_COL.getClobVal();
        ELSE
            :NEW.XML_COL_CLOB := NULL;
        END IF;
    END IF;
END;

-- Insert test data
INSERT INTO C##CFLTUSER.DATA_TYPES_TEST (ID, TEXT_COL, NUMBER_COL, DATE_COL, TIMESTAMP_COL, CLOB_COL, BLOB_COL, XML_COL, LONG_COL) VALUES (
    1,
    'Sample Text',
    12345.67,
    SYSDATE,
    SYSTIMESTAMP,
    TO_CLOB('Large text content...'),
    HEXTORAW('DEADBEEF'),
    XMLType('<employee><id>1</id><name>John</name></employee>'),
    'This is a long text column content that can store up to 2GB of data'
);
COMMIT;

-- Note: We generally cannot UPDATE a LONG column easily in SQL without PL/SQL or specific handling,
-- but we can insert new rows or update other columns.
