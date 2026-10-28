-- Use Case 8 (runs against SINKPDB): lose only a subset of the replicated rows.
DELETE FROM "EMPLOYEES" WHERE "DEPARTMENT" LIKE '%Engineering';
COMMIT;
