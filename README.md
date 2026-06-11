# Oracle → Oracle Replication with Confluent XStream CDC

This demo proves, end to end, which Oracle replication and migration scenarios are fully supported by the
**[Confluent Oracle XStream CDC Source Connector](https://docs.confluent.io/kafka-connectors/oracle-xstream-cdc-source/current/overview.html)** —
including the tricky ones: tables without primary keys, LOB columns, schema changes, and foreign-key ordering.

Everything runs locally with Docker Compose. One Oracle 19c container hosts both databases (as two PDBs),
so you can watch changes flow from source to destination in real time:

```text
      ┌─────────────────────────────────────────────────────────┐
      │         Oracle 19c EE — one container, two PDBs         │
      │                                                         │
      │    SOURCEPDB (DEMO schema)      SINKPDB (DEMO schema)   │
      └────────────┬───────────────────────────▲────────────────┘
                   │ 1. XStream Out (XOUT)     │ 4. upsert / delete
                   ▼                           │
       2. Oracle XStream CDC          3. Confluent JDBC
          Source Connector               Sink Connector
                   │                           ▲
                   └──▶ Kafka topics ──────────┘
                        xstream.DEMO.<TABLE>  (Avro)
```

---

## 🏗️ What gets deployed

| Container                    | Image                                                         | Role                                            |
| :--------------------------- | :------------------------------------------------------------ | :---------------------------------------------- |
| `oracle-19`                  | `container-registry.oracle.com/database/enterprise:19.19.0.0` | Oracle 19c EE hosting `SOURCEPDB` and `SINKPDB` |
| `broker1` … `broker3`        | `cp-server:7.9.5`                                             | 3-node Kafka cluster (KRaft)                    |
| `schema-registry`            | `cp-schema-registry:7.9.5`                                    | Avro schemas for keys and values                |
| `connect`                    | custom build on `cp-server-connect:7.9.5`                     | Kafka Connect + both connectors + custom SMT    |
| `control-center`             | `cp-enterprise-control-center-next-gen:2.2.0`                 | Web UI at <http://localhost:9021>               |
| `prometheus`, `alertmanager` | `cp-enterprise-prometheus` / `-alertmanager:2.2.0`            | Metrics backing Control Center                  |

<details>
<summary><b>Ports & credentials</b></summary>

| Endpoint                | Where                            | Credentials                            |
| :---------------------- | :------------------------------- | :------------------------------------- |
| Control Center          | <http://localhost:9021>          | —                                      |
| Kafka Connect REST      | <http://localhost:8083>          | —                                      |
| Schema Registry         | <http://localhost:8081>          | —                                      |
| Oracle listener         | `localhost:1521`                 | `sys / Welcome1` (as SYSDBA)           |
| Demo schema (both PDBs) | `…:1521/SOURCEPDB` & `…/SINKPDB` | `demo / DemoPass123`                   |
| Connector XStream user  | CDB root                         | `c##cfltuser / My_RandomPass192837465` |

</details>

<details>
<summary><b>Repository layout</b></summary>

| Folder | Contents                                                                      |
| :----- | :---------------------------------------------------------------------------- |
| `bin/` | Numbered scripts — run them in order                                          |
| `etc/` | Connector configs (`etc/connectors/`) and the Oracle driver RPMs you download |
| `sql/` | Setup DDL/seed data plus the SQL each use case executes                       |
| `smt/` | Source of the custom Single Message Transform used in Use Case 6              |
| `vol/` | Prometheus/Alertmanager config for Control Center                             |

</details>

---

## 🚀 Running the demo

### Prerequisites

- **Docker Desktop** (Compose v2+) with ~12 GB free disk (the Oracle EE image alone is ~7 GB).
- **Maven** — builds the custom SMT during startup.
- **jq** — used by the connector deployment script.
- An **Oracle Container Registry account**: at <https://container-registry.oracle.com> open
  **Database → enterprise**, accept the licence, then `docker login container-registry.oracle.com`.

<details>
<summary><b>Running on Intel / x86_64?</b></summary>

The compose file pins the ARM64 image tag (`19.19.0.0`, for Apple Silicon). On x86_64, change the
`oracle` service image tag to `19.3.0.0` in [docker-compose.yml](docker-compose.yml), and download
the `x86_64` RPMs in Step 1 instead of the `aarch64` ones.

</details>

### Step 1 — Download the Oracle client RPMs

Oracle's redistribution terms prevent shipping these in the repo. Download **both** and place them in `etc/`:

1. **Instant Client Basic** (el8 RPM for your CPU architecture) from the
   [Oracle Instant Client downloads](https://www.oracle.com/database/technologies/instant-client/downloads.html) page,
   e.g. `oracle-instantclient-basic-23.26.0.0.0-1.el8.aarch64.rpm`.
2. **libaio** (el8 RPM, same architecture) from the [Oracle Linux 8 BaseOS yum repo](https://yum.oracle.com/oraclelinux/8/index.html),
   e.g. `libaio-0.3.112-1.el8.aarch64.rpm`.

The startup script auto-detects both files by name — no configuration needed.

### Step 2 — Start the environment

```bash
./00_start_local_environment.sh
```

This builds the SMT, builds the Connect image (installing the Instant Client), and starts all containers.

⏳ **First run takes 10–20 minutes**: Oracle creates the database from scratch and configures XStream inside
the container. Wait until the container reports **healthy** status:

```bash
docker ps --filter name=oracle-19
```

> [!NOTE]
> `docker logs -f oracle-19` going quiet after `DATABASE IS READY TO USE!` is normal — it is the
> idle database alert log, not a hang. Container health is the signal that matters.

### Step 3 — Verify Oracle is ready

```bash
./bin/02_verify_oracle_status.sh
```

Expected: `✅ SYSTEM IS READY FOR DEMO` (XStream outbound server and capture process up, connector user present).

### Step 4 — Initialize the databases

> [!IMPORTANT]
> Run this **before** deploying the connectors — the connectors cache table metadata at startup.

```bash
./bin/03_initialize_databases.sh
```

This creates the six `DEMO` source tables and their seed data in `SOURCEPDB`, and pre-creates **all seven** sink tables in
`SINKPDB` as a mirror of the source schema (see the [migration approach](#-migration-approach-a-pre-created-target-schema) section).

### Step 5 — Deploy the connectors

```bash
./bin/04_deploy_connectors.sh
```

Both connectors should report `deployed successfully`. You can watch them (and the `xstream.DEMO.*` topics)
in Control Center at <http://localhost:9021> — both `OracleXStreamSourceConnector` and `JdbcSinkConnector`
should be **Running**.

---

## 🗺️ Migration approach: a pre-created target schema

This demo provisions the complete target schema in `SINKPDB` up front (Step 4) and runs the sink
connector with `auto.create: false`. That mirrors how corporate migrations actually work: the target
schema is created and reviewed by DBA tooling, and CDC moves the **data** — relying on a connector to
invent the target DDL is convenient for streaming pipelines, but it produces generic column types and no
constraints.

Every sink table mirrors its source table column-for-column, with five deliberate differences
(all visible in [sql/setup/03_create_oracle_sink_tables.sql](sql/setup/03_create_oracle_sink_tables.sql)):

| Difference on the target                        | Why                                                                          |
| :---------------------------------------------- | :--------------------------------------------------------------------------- |
| `LONG` columns become `CLOB`                    | Oracle's own guidance — see below                                            |
| `PRIMARY KEY` added to keyless tables           | The sink upserts via `MERGE`; see below                                      |
| `NOT NULL` relaxed on `CLOB_TEST.CLOB_REQUIRED` | Oracle treats `''` as `NULL`: `EMPTY_CLOB()` arrives as `NULL` (`ORA-01400`) |
| XML/RAW shadow columns + re-cast trigger        | `XMLTYPE` is not captured by XStream; `RAW` travels as hex                   |
| Three metadata columns on every table           | `MAQUINA_ID`, `SOURCETIMESTAMP`, `SINKTIMESTAMP` — per-record traceability   |

**Leaving `LONG` behind.** The sink maps the source's `LONG` column to `CLOB`. This is not a
workaround — it is Oracle's explicit recommendation: *"Do not create tables with `LONG` columns. Use
LOB columns (`CLOB`, `NCLOB`, `BLOB`) instead. `LONG` columns are supported only for backward
compatibility"*, and *"Oracle also recommends that you convert existing `LONG` columns to LOB
columns"*
([Oracle Database 19c SQL Language Reference — Data Types](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/Data-Types.html)).
Oracle dedicates an entire chapter to this migration
([SecureFiles and Large Objects Developer's Guide — Migrating Columns from LONGs to LOBs](https://docs.oracle.com/en/database/oracle/oracle-database/19/adlob/migrating-columns-from-LONGs-to-LOBs.html)).
A migration is precisely the right moment to do it.

**The target ends up better constrained than the source.** `DEPARTMENTS` and `JOBS` have no primary
key at the source (use cases 2 and 3 exist to prove replication still works). On the target, both get
a real `PRIMARY KEY` on the column that acts as the record key. This is required for correctness — the
sink upserts via `MERGE`, and duplicate keys would fail with `ORA-30926` — and it is also an upgrade:
the migration leaves the data *better* governed than it started.

`auto.evolve` remains **enabled**: when use case 1 adds a column at the source, the sink table evolves
live. And thanks to `topics.regex` + `table.include.list`, onboarding a brand-new table needs exactly
one manual step: pre-create its sink table, then create and use it at the source.

---

## 🧪 The use cases

Each use case is a single script: it applies changes to `SOURCEPDB`, then automatically verifies they
arrive in `SINKPDB`, reporting replication timing per step. A green `✅ COMPLETED` line means everything
replicated correctly.

| # | What it proves                                          | Table(s)                       | Script                     |
| : | :------------------------------------------------------ | :----------------------------- | :------------------------- |
| 1 | DML + DDL + complex types on a normal PK table          | `EMPLOYEES`, `DATA_TYPES_TEST` | `bin/05_run_use_case_1.sh` |
| 2 | Table with **no PK** — key derived from a unique index  | `DEPARTMENTS`                  | `bin/06_run_use_case_2.sh` |
| 3 | Table with **no PK and no unique index** — manual key   | `JOBS`                         | `bin/07_run_use_case_3.sh` |
| 4 | CLOB values: populated vs `NULL` vs `EMPTY_CLOB()`      | `CLOB_TEST`                    | `bin/08_run_use_case_4.sh` |
| 5 | Parent/child **foreign keys** with out-of-order arrival | `CUSTOMERS`, `ORDERS`          | `bin/09_run_use_case_5.sh` |
| 6 | Updates that **don't touch** a LOB column (custom SMT)  | `DATA_TYPES_TEST`              | `bin/10_run_use_case_6.sh` |

> [!NOTE]
> Run the use cases **in order** on a fresh environment (Use Case 6 updates a row inserted by Use Case 1).
> They are designed as a single pass — to replay the demo, [reset the environment](#-resetting-the-environment) first.

Every sink table also receives three metadata columns, so you can trace each record: `MAQUINA_ID`
(source database id), `SOURCETIMESTAMP` (when the change happened at the source) and `SINKTIMESTAMP`
(when it was written to the sink).

<details>
<summary><b>Query the sink database yourself</b></summary>

After any use case, you can inspect `SINKPDB` directly (adapt the query to the table you want to check):

```bash
docker exec -i oracle-19 sqlplus -S demo/DemoPass123@//localhost:1521/SINKPDB \
  <<< 'SELECT "FIRST_NAME", "SALARY", "SOURCETIMESTAMP", "SINKTIMESTAMP" FROM "EMPLOYEES" WHERE "EMPLOYEE_ID" = 1;'
```

Note the double quotes: the sink connector creates tables and columns with case-sensitive identifiers.

</details>

---

### Use case 1 — Basic data flow: DML, DDL & complex types

The bread and butter: a table with a primary key (`EMPLOYEES`), plus a table full of Oracle-specific
types (`DATA_TYPES_TEST`).

```bash
./bin/05_run_use_case_1.sh
```

| Step | Change applied to SOURCEPDB                                     | Verified in SINKPDB                                |
| :--- | :-------------------------------------------------------------- | :------------------------------------------------- |
| 1    | `UPDATE` employee 1's salary to 90 000                          | Salary updated on the matching row                 |
| 2    | `DELETE` employee 3                                             | Row removed (tombstone → delete)                   |
| 3    | DDL: `ADD COLUMN PHONE_NUMBER`, drop another, insert employee 4 | New column auto-added (`auto.evolve`), row arrives |
| 4    | `INSERT` a row with `XMLTYPE`, `CLOB`, `BLOB`, `LONG`, `RAW`    | Full row replicated, native types reconstructed    |

> [!NOTE]
> `auto.evolve` only **adds** columns on the sink — dropped source columns are left in place by design.

<details>
<summary><b>How XMLTYPE, RAW and LONG make it across</b></summary>

`XMLTYPE` is not supported by the XStream connector, and `RAW` needs a text-safe representation to
survive the trip, so the demo uses **shadow columns** maintained by triggers:

- **Source** ([sql/setup/01_create_tables.sql](sql/setup/01_create_tables.sql)): trigger `trg_data_types_test`
  copies `XML_COL` → `XML_COL_CLOB` (via `getClobVal()`) and `RAW_COL` → `RAW_COL_VARCH` (via `RAWTOHEX()`)
  on every insert/update. The capturable CLOB/VARCHAR2 surrogates travel through Kafka.
- **Sink** ([sql/setup/03_create_oracle_sink_tables.sql](sql/setup/03_create_oracle_sink_tables.sql)): trigger
  `trg_sync_complex_types` rebuilds the native columns with `XMLTYPE(XML_COL_CLOB)` and `HEXTORAW(RAW_COL_VARCH)`.

</details>

<details>
<summary><b>Key connector configuration</b></summary>

Source ([etc/connectors/source-connector.json](etc/connectors/source-connector.json)):

- `transforms.flatten` (`io.debezium.transforms.ExtractNewRecordState`) — flattens the Debezium-style
  `before`/`after` envelope into the flat record the JDBC sink expects, and adds the
  `SOURCETIMESTAMP`/`MAQUINA_ID` metadata fields.
- `transforms.convertTS` (`TimestampConverter`) — turns the source timestamp into a Connect `Timestamp`
  so it lands as a real `TIMESTAMP` column.
- `decimal.handling.mode: precise` — Oracle `NUMBER(p,s)` travels as an exact decimal and lands as `NUMBER` on the target (no float rounding, IDs above 2^53 stay exact). Requires every source `NUMBER` to declare its precision — bare `NUMBER` would be emitted as a struct the JDBC sink cannot write.
- `table.include.list: DEMO[.].*` — captures every table in the `DEMO` schema.

Sink ([etc/connectors/sink-connector.json](etc/connectors/sink-connector.json)):

- `insert.mode: upsert` + `pk.mode: record_key` — inserts and updates use the record key as PK.
- `delete.enabled: true` — tombstones from the source become `DELETE`s.
- `auto.evolve: true` — pre-created sink tables gain new columns automatically when the source schema changes (`auto.create` is `false`: the schema is provisioned up front).
- `transforms.routeTopic` (`RegexRouter`) — strips the `xstream.DEMO.` prefix so topic
  `xstream.DEMO.EMPLOYEES` writes to table `EMPLOYEES`.
- `transforms.insertTS` (`InsertField`) — stamps `SINKTIMESTAMP` on every record for latency measurement.

</details>

---

### Use case 2 — No primary key, but a unique index

`DEPARTMENTS` has no PK — only a unique index on `DEPT_ID` (plus other, non-unique indexes). The source
connector **automatically detects the unique index** and uses it as the Kafka message key, so updates and
deletes still work.

```bash
./bin/06_run_use_case_2.sh
```

| Step | Change applied to SOURCEPDB              | Verified in SINKPDB              |
| :--- | :--------------------------------------- | :------------------------------- |
| 1    | `INSERT` department 40 (*Finance*)       | Row count increases by 1         |
| 2    | `UPDATE` department 20's name to *Legal* | Name updated on the matching row |
| 3    | `DELETE` department 20                   | Row count decreases by 1         |

<details>
<summary><b>Key connector configuration</b></summary>

- The connector user has PDB-level access to `SYS.DBA_INDEXES`, which lets the source connector discover
  unique indexes for keyless tables and derive the message key — no configuration per table needed.
- Sink: `pk.mode: record_key` maps that derived key to the sink table's primary key;
  `delete.enabled: true` makes index-keyed deletes propagate.

</details>

---

### Use case 3 — No primary key, no unique index

`JOBS` has neither a PK nor a unique index, so there is nothing to auto-detect. The key is **declared
manually** in the source connector: `message.key.columns: DEMO.JOBS:JOB_ID`.

```bash
./bin/07_run_use_case_3.sh
```

| Step | Change applied to SOURCEPDB           | Verified in SINKPDB               |
| :--- | :------------------------------------ | :-------------------------------- |
| 1    | `INSERT` job `AD_VP`                  | Row count increases by 1          |
| 2    | `UPDATE` `AD_VP` max salary to 35 000 | Value updated on the matching row |
| 3    | `DELETE` job `ST_CLERK`               | Row count decreases by 1          |

> [!TIP]
> Define the key column as `NOT NULL` in Oracle — otherwise Avro wraps the key in a union type
> (`{"string": "..."}`), which complicates downstream key matching.

---

### Use case 4 — CLOB replication: populated, NULL and empty

`CLOB_TEST` exercises every CLOB state. The script creates the source table mid-demo (the sink table is pre-created at Step 4), inserts three rows covering all
combinations, then flips each state via updates — verifying the sink after every change.

```bash
./bin/08_run_use_case_4.sh
```

| Row | `CLOB_NULLABLE` (source) | `CLOB_REQUIRED` (source, `NOT NULL`) | Expected in sink |
| :-- | :----------------------- | :----------------------------------- | :--------------- |
| 1   | text                     | `EMPTY_CLOB()`                       | text / `NULL`    |
| 2   | `NULL`                   | text                                 | `NULL` / text    |
| 3   | `NULL`                   | `EMPTY_CLOB()`                       | `NULL` / `NULL`  |

The update phase then proves transitions work in both directions: value → `NULL`, `NULL` → value,
empty → value, value → empty, and that updating a non-CLOB column leaves CLOBs untouched.

> [!IMPORTANT]
> **Oracle treats an empty string as `NULL`** — so `EMPTY_CLOB()` arrives at the sink as `NULL`; the
> "empty but not null" distinction cannot survive JDBC replication into Oracle. That is why the
> pre-created sink table declares `CLOB_REQUIRED` **nullable** (a `NOT NULL` sink column would
> reject those rows with `ORA-01400`).

---

### Use case 5 — Foreign keys & out-of-order events

`CUSTOMERS` (parent) and `ORDERS` (child) are linked by a foreign key. The script deliberately inserts a
**child before its parent** in one transaction to prove the pipeline heals itself.

```bash
./bin/09_run_use_case_5.sh
```

| Step | Change applied to SOURCEPDB                                 | Verified in SINKPDB                        |
| :--- | :---------------------------------------------------------- | :----------------------------------------- |
| 1    | `INSERT` customer 1, then order 101                         | Both rows arrive                           |
| 2    | `UPDATE` the customer's name and the order's amount         | Both updates arrive                        |
| 3    | `INSERT` **order 102 before customer 2** (same transaction) | Both rows arrive — retries handle ordering |
| 4    | `DELETE` order 101, then customer 1                         | Both deletes arrive, FK never violated     |

<details>
<summary><b>How out-of-order arrival is handled</b></summary>

Three mechanisms work together:

1. **Smart retries** (sink): `tasks.max: 4`, `batch.size: 1`, `max.retries: 30`, `retry.backoff.ms: 2000`.
   If an order hits an FK violation because its customer hasn't arrived yet, only that record retries
   (up to ~60 s) while other tasks keep processing — the parent lands, then the retry succeeds.
2. **Deferrable constraints** (database): the FK on both PDBs is `DEFERRABLE INITIALLY DEFERRED`, so
   Oracle validates at `COMMIT`, tolerating any insert order inside a transaction.
3. **Dead letter queue** (sink): `errors.tolerance: all` with DLQ topic `JDBC_SINK_DLQ` — a record that
   exhausts all retries is parked there instead of stopping the pipeline.

</details>

---

### Use case 6 — Partial updates that skip a LOB column

When an Oracle `UPDATE` doesn't modify a LOB column, XStream **does not include the LOB** in the change
record. The source connector emits a placeholder (`__cflt_unavailable_value`) instead — and without
intervention the sink would overwrite real data with that placeholder. A **custom SMT** fixes this.

Requires Use Case 1 (it updates the complex-types row inserted there).

```bash
./bin/10_run_use_case_6.sh
```

| Step | Change applied to SOURCEPDB                         | Verified in SINKPDB                                   |
| :--- | :-------------------------------------------------- | :---------------------------------------------------- |
| 1    | `UPDATE` only `NUMBER_COL` on a row that has a CLOB | `NUMBER_COL` updated **and** the CLOB value untouched |

<details>
<summary><b>How the custom SMT works</b></summary>

- Source: LOB capture is a built-in connector feature (`lob.enabled` is set defensively);
  `unavailable.value.placeholder: __cflt_unavailable_value` marks LOBs that were not part of the update
  with a recognizable sentinel.
- Sink: the custom SMT `io.confluent.csta.smt.RemoveAttributeWithValue` (source in [smt/](smt/), built
  automatically by `00_start_local_environment.sh`) **removes any field** whose value matches the
  placeholder (raw or base64 form) before the record reaches the JDBC writer.
- With the field gone, the generated `UPDATE` statement simply omits that column — the sink database
  keeps its current value.

</details>

---

## 🧹 Resetting the environment

To wipe everything (containers, Kafka topics, and the Oracle data volume) and start fresh:

```bash
docker compose down -v
```

Then start again from [Step 2](#step-2--start-the-environment).

<details>
<summary><b>Troubleshooting</b></summary>

- **`02_verify_oracle_status.sh` says NOT READY** right after the container turns healthy: the startup
  hook ([bin/01b_start_xstream.sh](bin/01b_start_xstream.sh)) may still be restarting the XStream capture —
  wait ~1 minute and rerun. It also runs on every container restart, so a plain `docker compose restart oracle`
  recovers a disabled capture process.
- **A use-case script times out** but the connectors show *Running*: check the DLQ topic `JDBC_SINK_DLQ`
  and the Connect log (`docker logs connect`) — `errors.tolerance: all` keeps the sink running even when
  individual records fail.
- **Re-running a use case fails**: expected — the SQL scripts are one-shot (e.g. they delete a specific
  row or add a column that now already exists). Reset the environment to replay.
- **Adding your own table?** Pre-create its mirror in `SINKPDB` first (the sink runs with
  `auto.create: false`); then create the table in `SOURCEPDB.DEMO` — `table.include.list` and
  `topics.regex` pick it up automatically. Without the sink table, its records park in the DLQ.

</details>

---

## 📋 Disclaimer

This project is a demo/reference only — **not** production-ready code. Always follow the official
documentation of the referenced products.
