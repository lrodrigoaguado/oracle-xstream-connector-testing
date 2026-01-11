-- Deletes for Use Case 4: Referential Integrity

-- 1. Delete Child first
DELETE FROM DEMO.ORDERS WHERE ORDER_ID = 101;
COMMIT;

-- 2. Delete Parent after Child is gone
DELETE FROM DEMO.CUSTOMERS WHERE CUSTOMER_ID = 1;
COMMIT;

-- 3. Attempt Delete Parent while Child exists (Will fail in Oracle and Postgres if not deferred or handled)
-- DELETE FROM DEMO.CUSTOMERS WHERE CUSTOMER_ID = 2; -- This would normally fail
