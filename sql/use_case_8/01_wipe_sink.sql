-- Use Case 8 (runs against SINKPDB): simulate losing the replicated data.
-- Only the sink is touched; SOURCEPDB.DEMO.EMPLOYEES keeps all of its rows.
DELETE FROM "EMPLOYEES";
COMMIT;
