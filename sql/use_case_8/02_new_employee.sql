-- Use Case 8 (runs against SOURCEPDB): a regular change made after the snapshot.
-- Column list is explicit so it works whether or not Use Case 1 changed the table.
INSERT INTO DEMO.EMPLOYEES (EMPLOYEE_ID, FIRST_NAME, LAST_NAME, EMAIL, SALARY, DEPARTMENT)
VALUES (8, 'Grace', 'Hopper', 'grace.hopper@example.com', 95000.00, 'Engineering');
COMMIT;
