-- Operations for Use Case 3: No Primary Key with Deletion Support
-- These operations demonstrate captured events for tables without defined keys
-- where deletes are supported by extracting a key at the source.

-- 1. Insert seed data (redundant with setup but good for testing)
INSERT INTO C##CFLTUSER.JOBS (JOB_ID, JOB_TITLE, MIN_SALARY, MAX_SALARY) VALUES ('AD_VP', 'Administration Vice President', 15000, 30000);
COMMIT;

-- 2. Update a job
UPDATE C##CFLTUSER.JOBS SET MAX_SALARY = 35000 WHERE JOB_ID = 'AD_VP';
COMMIT;
