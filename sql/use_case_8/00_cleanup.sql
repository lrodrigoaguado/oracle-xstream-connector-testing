-- Use Case 8 (runs against SOURCEPDB): remove the employee added by a previous run,
-- so step 3 always inserts a genuinely new row and the use case can be replayed.
DELETE FROM DEMO.EMPLOYEES WHERE EMPLOYEE_ID = 8;
COMMIT;
