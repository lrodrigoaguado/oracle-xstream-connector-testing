-- Operations for Use Case 7: keyless table with a NULL message key.
-- AUDIT_LOG has no PK, no unique index and no candidate key column, and the
-- source connector has NO message.key.columns entry for it. Every captured
-- record is therefore emitted with a NULL key. The JDBC sink (delete.enabled +
-- pk.mode=record_key) would crash on such a record inside put() -- the DLQ does
-- NOT cover that stage -- so the sink's Filter$Key SMT (missing.or.null.behavior
-- =fail) intercepts each null-key record in the transform stage and routes it to
-- the JDBC_SINK_DLQ topic, keeping the task RUNNING.

INSERT INTO DEMO.AUDIT_LOG (CREATED_AT, ACTION, ENTITY, DETAILS)
VALUES ('2026-09-03T10:00:00Z', 'LOGIN',  'USER:jdoe',   'Login from 10.0.0.15');
INSERT INTO DEMO.AUDIT_LOG (CREATED_AT, ACTION, ENTITY, DETAILS)
VALUES ('2026-09-03T10:01:12Z', 'UPDATE', 'ORDER:101',   'Status changed to SHIPPED');
INSERT INTO DEMO.AUDIT_LOG (CREATED_AT, ACTION, ENTITY, DETAILS)
VALUES ('2026-09-03T10:02:47Z', 'DELETE', 'SESSION:ab12','Session expired');
COMMIT;
