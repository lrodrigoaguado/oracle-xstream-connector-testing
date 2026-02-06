-- 1. Insert with Non-Null Nullable, Empty Required
INSERT INTO DEMO.CLOB_TEST (ID, DESCRIPTION, CLOB_NULLABLE, CLOB_REQUIRED)
VALUES (1, 'Standard Insert', 'This is a nullable CLOB', EMPTY_CLOB());

-- 2. Insert with Null Nullable, Non-Null Required
INSERT INTO DEMO.CLOB_TEST (ID, DESCRIPTION, CLOB_NULLABLE, CLOB_REQUIRED)
VALUES (2, 'Null Insert', NULL, 'Required CLOB cannot be null');

-- 3. Insert with Null Nullable, Empty Required (Variation)
INSERT INTO DEMO.CLOB_TEST (ID, DESCRIPTION, CLOB_NULLABLE, CLOB_REQUIRED)
VALUES (3, 'Empty Clob Insert', NULL, EMPTY_CLOB());

COMMIT;
