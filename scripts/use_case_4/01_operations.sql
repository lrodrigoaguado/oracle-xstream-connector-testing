-- Operations for Use Case 4: Referential Integrity

-- 1. Standard Insert (Parent then Child)
INSERT INTO C##CFLTUSER.CUSTOMERS (CUSTOMER_ID, CUSTOMER_NAME, EMAIL) VALUES (1, 'John Doe', 'john.doe@example.com');
INSERT INTO C##CFLTUSER.ORDERS (ORDER_ID, CUSTOMER_ID, TOTAL_AMOUNT) VALUES (101, 1, 250.50);
COMMIT;

-- 2. Update Parent
UPDATE C##CFLTUSER.CUSTOMERS SET CUSTOMER_NAME = 'John Updated' WHERE CUSTOMER_ID = 1;
COMMIT;

-- 3. Update Child
UPDATE C##CFLTUSER.ORDERS SET TOTAL_AMOUNT = 300.00 WHERE ORDER_ID = 101;
COMMIT;

-- 4. Potential Transient Violation (Insert Child then Parent in the same transaction)
-- Because the constraint is DEFERRABLE INITIALLY DEFERRED, Oracle allows this until COMMIT.
-- The Sink connector might process these in any order or via retries if they arrive separately.
INSERT INTO C##CFLTUSER.ORDERS (ORDER_ID, CUSTOMER_ID, TOTAL_AMOUNT) VALUES (102, 2, 150.00);
INSERT INTO C##CFLTUSER.CUSTOMERS (CUSTOMER_ID, CUSTOMER_NAME, EMAIL) VALUES (2, 'Jane Smith', 'jane.smith@example.com');
COMMIT;
