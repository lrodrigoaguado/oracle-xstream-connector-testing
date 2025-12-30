-- Operations for Use Case 2: No Primary Key
-- These operations demonstrate captured events for tables without defined keys.

-- 1. Insert a new department
INSERT INTO C##CFLTUSER.DEPARTMENTS (DEPT_ID, DEPT_NAME, LOCATION_ID) VALUES (40, 'Finance', 4000);
COMMIT;

-- 2. Update a department
UPDATE C##CFLTUSER.DEPARTMENTS SET DEPT_NAME = 'Legal' WHERE DEPT_ID = 20;
COMMIT;
