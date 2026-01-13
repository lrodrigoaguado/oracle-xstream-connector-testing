-- Add a new column
ALTER TABLE DEMO.EMPLOYEES ADD (PHONE_NUMBER VARCHAR2(20));

ALTER TABLE DEMO.EMPLOYEES DROP COLUMN HIRE_DATE;

-- Insert data with new column
INSERT INTO DEMO.EMPLOYEES VALUES
(4, 'Alice', 'Williams', 'alice@example.com', 90000.00, 'Engineering', '555-1234');
COMMIT;
