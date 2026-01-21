-- Partial Update for Use Case 5
-- Update a non-CLOB column (NUMBER_COL) in a row with CLOB data (ID=2)
UPDATE DEMO.DATA_TYPES_TEST SET NUMBER_COL = 99999.99 WHERE ID = 2;
COMMIT;
