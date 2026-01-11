-- Operations for Use Case 1: Complex Data Types
-- The table and trigger are now created during initial setup to ensure capture stability.

-- Insert test data
INSERT INTO DEMO.DATA_TYPES_TEST (ID, TEXT_COL, NUMBER_COL, DATE_COL, TIMESTAMP_COL, CLOB_COL, BLOB_COL, XML_COL, LONG_COL) VALUES (
    2,
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
