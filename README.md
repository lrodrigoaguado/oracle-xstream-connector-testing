# 🚀 Oracle XStream CDC Connector Testing Environment

A comprehensive testing environment for the **Confluent Oracle XStream CDC Source Connector**, enabling real-time change data capture (CDC) from Oracle Database to Apache Kafka.

## 📋 Disclaimer

The code and/or instructions here available are NOT intended for production usage. It's only meant to serve as an example or reference and does not replace the need to follow actual and official documentation of referenced products.

---

## 🏗️ Quick Start

This guide will get you up and running in **under 10 minutes**.

### Prerequisites

1. **Docker Desktop** (with Docker Compose v2+).
2. **Maven** (to build the custom SMT).

### Step 1: Download Oracle Drivers

Due to redistribution restrictions, you must manually download the Oracle Instant Client Basic RPM and place it in the etc/ folder.

1. Go to the [Oracle Instant Client Downloads](https://www.oracle.com/database/technologies/instant-client/downloads.html) page.
2. Download the **Basic** RPM for your architecture (e.g., `oracle-instantclient-basic-21.x-1.x86_64.rpm`).
3. Place the `.rpm` file in the `etc/` folder of this project.

### Step 2: Start the Local Environment

Run the following script to start the entire Docker environment (Kafka, Oracle, Postgres, Connect, etc.):

```bash
./00_start_local_environment.sh
```

The containers will start up quickly, but the deployment of the XStream Out server and capture process may take a few minutes.. Please, check the initialization by running:

```bash
docker logs -f oracle-init
```

The installation will have finished when you can read the message:

```bash
================================================================================
>> [XSTREAM SETUP] XStream setup completed successfully.
================================================================================
```

### Step 3: Verify and Initialize Oracle

1. **Verify Oracle Status**: Run the verification script to confirm the database and XStream are configured correctly.

Make sure both the Oracle database is 100% ready and the local environment is working. Then, run the script

```bash
./bin/02_verify_oracle.sh
```

You should see: `✅ SYSTEM IS READY FOR DEMO`.

2. **Initialize the Databases**:
   > [!IMPORTANT]
   > **CRITICAL STEP**: This **MUST** be run before deploying the connectors. The connector caches table metadata at startup; if the tables skip this step, the Sink Connector will fail due to missing keys.

   ```bash
   ./bin/03_initialize_databases.sh
   ```

### Step 4: Deploy the Connectors

Deploy both the Source and Sink connectors:

```bash
./bin/04_deploy_connectors.sh
```

### Step 5: Access the UI

You can access the Confluent Control Center at <http://localhost:9021> and check that all resources are up and running and you have both connectors (`OracleXStreamSourceConnector` and `JdbcSinkConnector`) in a `Running` state.

---

## 📊 Monitoring & Metadata Fields

The connectors inject three metadata columns into every destination table in Postgres to help track the replication process:

| Column Name       | Origin           | Description                                                        |
| :---------------- | :--------------- | :----------------------------------------------------------------- |
| `MAQUINA_ID`      | Source Connector | Source database identifier.                                        |
| `SOURCETIMESTAMP` | Source Connector | Timestamp when the change occurred in Oracle.                      |
| `SINKTIMESTAMP`   | Sink Connector   | Timestamp when the record was written to Postgres.                 |

---

## 🧪 Use Cases

All use cases assume you have completed the **Quick Start** steps (1-6) successfully.

---

### Use Case 1: Basic Data Flow (DML, DDL, Complex Types)

Captures standard database operations including `UPDATE`, `DELETE`, and schema changes (`DDL`), alongside complex Oracle-specific types like `XMLType`, `CLOB`, `RAW`, and `LONG`.

- **Mechanism**: Replicated using the `EMPLOYEE_ID` **Primary Key**.
- **Oracle Action**: Updates salary, deletes a record, adds a column, and inserts complex types.

```bash
./bin/05_run_use_case_1.sh
```

The script will execute the SQL scripts in the "sql/use_case_1" subfolder, which will perform DML and DDL operations in Oracle and automatically verify replication to Postgres, reporting timing for each step.

- **Verification**:

  ```bash
  docker exec -it postgres psql -U test-connector -d test-connector -c 'SELECT "FIRST_NAME", "SALARY" FROM EMPLOYEES WHERE "EMPLOYEE_ID" = 1;'
  ```

#### 🔑 Use Case 1: Key Connector Parameters

**Source Connector:**

- `io.debezium.transforms.ExtractNewRecordState`: **Crucial SMT (Single Message Transform)**. It flattens the complex Debezium-style structure (which contains `before`, `after`, and `source` metadata) into a simple, flat record. This is essential because the standard JDBC Sink Connector expects a flat message format.
- `org.apache.kafka.connect.transforms.TimestampConverter`: Used to convert the source timestamp from a raw number to a standard Kafka/Connect **Timestamp** type, ensuring it is correctly created as a `TIMESTAMP` column in Postgres.
- `decimal.handling.mode: double`: Ensures Oracle numeric types are correctly mapped to double precision in Kafka and Postgres.
- `table.include.list: DEMO[.].*`: Ensures all tables in the `DEMO` schema are captured.
- `database.out.server.name: XOUT`: Connects to the specific Oracle XStream Outbound Server.

**Sink Connector (Metadata & Routing)**:

- `org.apache.kafka.connect.transforms.InsertField`: Automatically injects the `SINKTIMESTAMP` into the record as it is written to the database, allowing for end-to-end latency measurement.
- `org.apache.kafka.connect.transforms.RegexRouter`: Standardizes the destination table names in Postgres by stripping the `xstream.DEMO.` prefix from the Kafka topic names.
- `insert.mode: upsert`: Required to handle both INSERT and UPDATE operations correctly.
- `delete.enabled: true`: Combined with the source's `drop.tombstones=false`, this allows DELETEs to propagate to Postgres.
- `pk.mode: record_key`: Uses the key generated by the source connector as the Primary Key in Postgres.
- `auto.create: true` & `auto.evolve: true`: Enables the connector to automatically create the destination tables and, more importantly, **evolve the schema** (add columns) when DDL changes occur in Oracle.

#### ⚠️ Important Caveats regarding Oracle Technologies

#### ⚠️ Strategies for Unsupported Oracle Data Types

The following limitations are inherent to the **Oracle Database** and **Oracle XStream API**. We demonstrate two different architectural approaches to overcome these limitations.

##### Approach A: Trigger-based Transformation (Real-time shadow columns)

This approach uses Oracle triggers to automatically populate "shadow" columns of supported types (`CLOB`, `VARCHAR2`) whenever the base table is changed.

> [!TIP]
> **XMLType (via Triggers)**:
>
> - **Source**: Oracle **Trigger** (`trg_data_types_test`) copies `XMLTYPE` to a `CLOB` column (`XML_COL_CLOB`).
> - **Destination**: Postgres **Trigger** (in `03_create_postgres_tables.sql`) automatically casts the text back into a native `xml` column (`XML_COL`).
>
> **RAW (via Triggers)**:
>
> - **Source**: Oracle **Trigger** (`trg_data_types_test`) converts `RAW` data to a Hex string in `RAW_COL_VARCH`.
> - **Destination**: Postgres **Trigger** (in `03_create_postgres_tables.sql`) decodes the Hex string back into binary (`BYTEA`) in `RAW_COL`.

##### Approach B: View-based Transformation (Materialized View Casting)

This alternative approach avoids triggers on the base table by using a **Materialized View** that performs the casting natively in its definition. XStream captures the MV as a standard table.

> [!TIP]
> **The `DATA_TYPES_MV` Strategy**:
> - **Mechanism**: A Materialized View ([`DATA_TYPES_MV`](file:///Users/luisrodrigoaguado/Dev/Demos/oracle-xstream-connector-testing/sql/setup/01_create_tables.sql)) selects from the base table and applies `RAWTOHEX()` and `.getClobVal()` in the `SELECT` list.
> - **Capture**: XStream is configured to capture the MV table.
> - **Benefit**: Decouples the transformation logic from the base table and leverages native Oracle SQL casting.

---

### Use Case 2: No-PK with Unique Index

Handles replication for tables that lack a Primary Key but possess a **Unique Index**, allowing for full `UPDATE` and `DELETE` support.

- **Mechanism**: Automatically detects and uses the `DEPT_ID` **Unique Index** as the Kafka message key.
- **Oracle Action**: Inserts, updates, and deletes records in the `DEPARTMENTS` table.
- **Table**: `DEPARTMENTS` (Unique Index on `DEPT_ID`).

```bash
./bin/06_run_use_case_2.sh
```

- **Verification**:

  ```bash
  docker exec -it postgres psql -U test-connector -d test-connector -c 'SELECT * FROM DEPARTMENTS WHERE "DEPT_ID" = 20;'
  ```

#### 🔑 Use Case 2: Key Connector Parameters

**Source Connector:**

- **Automatic Detection**: When the source connector is granted PDB-level access to `SYS.DBA_INDEXES`, it automatically detects unique indexes for tables without primary keys and uses them as the Kafka message key.

**Sink Connector:**

- `pk.mode: record_key`: Essential for mapping the unique-index-based key into a Postgres Primary Key.
- `delete.enabled: true`: Required to propagate deletes identified by the Unique Index.

---

### Use Case 3: No-PK (Manual Key Derivation)

Showcases replication for tables without any PK or Unique Index by manually defining the key in the connector configuration.

- **Mechanism**: Uses the `message.key.columns` property to manually assign `JOB_ID` as the replication key.
- **Oracle Action**: Performs DML operations on the `JOBS` table.
- **Table**: `JOBS` (No PK, uses `message.key.columns: DEMO.JOBS:JOB_ID`).

```bash
./bin/07_run_use_case_3.sh
```

- **Verification**:

  ```bash
  docker exec -it postgres psql -U test-connector -d test-connector -c "SELECT * FROM JOBS WHERE \"JOB_ID\" = 'AD_VP';"
  ```

#### 🔑 Use Case 3: Key Connector Parameters

**Source Connector:**

- `message.key.columns: DEMO.JOBS:JOB_ID;`: Manually instructs the connector to use specific column(s) as the message key for tables lacking both a primary key and a unique index.

> [!IMPORTANT]
> **Schema Tip**: To avoid Avro "union" wrappers (like `{"string": "..."}`) in your Kafka keys, ensure the source column is defined as **`NOT NULL`** in Oracle.

**Sink Connector:**

- `pk.mode: record_key`: Maps the manually defined key to the Postgres Primary Key.
- `delete.enabled: true`: Enables delete support using the manually derived key.

---

### Use Case 4: Referential Integrity (Smart Retries)

Demonstrates how to handle **Foreign Key** relationships between parent and child tables, ensuring data consistency even when events arrive out of order.

- **Mechanism**: Combines **Smart Retries** in the Sink Connector with **Deferrable Constraints** in both databases.
- **Oracle Action**: Inserts parent (`CUSTOMERS`) and child (`ORDERS`) records, followed by coordinated updates and deletes.
- **Tables**: `CUSTOMERS` (Parent), `ORDERS` (Child).

```bash
./bin/08_run_use_case_4.sh
```

- **Verification**:

  ```bash
  docker exec -it postgres psql -U test-connector -d test-connector -c 'SELECT c."CUSTOMER_NAME", o."TOTAL_AMOUNT" FROM CUSTOMERS c JOIN ORDERS o ON c."CUSTOMER_ID" = o."CUSTOMER_ID" WHERE c."CUSTOMER_ID" = 1;'
  ```

### 4.1 The Three Pillars of Referential Integrity CDC

To handle FK constraints between `CUSTOMERS` (Parent) and `ORDERS` (Child), we implement three key strategies:

#### Pillar A: Smart Connector Retries

We configure the JDBC Sink to handle transient FK violations (e.g., when a child record arrives before its parent).

- **`tasks.max > 1`**: Essential so one task can continue processing the Parent topic while another is retrying the Child.
- **`max.retries`**: Set high (e.g., 10+).
- **`retry.backoff.ms`**: Set to 3000ms. This creates a ~30-second window for the parent record to arrive and be processed.

#### Pillar B: Deferrable Constraints

Both Oracle and Postgres are configured with **Deferrable Constraints** (`DEFERRABLE INITIALLY DEFERRED`).

- This allows the database to skip constraint validation until the transaction `COMMIT`.
- In the JDBC Sink, which processes in batches, this allows parent and child records within the same batch to be inserted in any order.

#### Pillar C: Dead Letter Queue (DLQ)

For permanent failures (e.g., data truly missing from source), we use a DLQ to prevent the pipeline from crashing.

- **`errors.deadletterqueue.topic.name`**: `dlq_oracle_sink`
- **`errors.tolerance`**: `all`

#### 🔑 Use Case 4: Key Connector Parameters

**Sink Connector (Smart Retries):**

- `tasks.max: 4`: Allows multiple tasks to process different records in parallel.
- `batch.size: 1`: By processing records one at a time, the connector ensures that if a Foreign Key violation occurs, only that specific record is retried (or sent to the DLQ), without impacting unrelated records in a larger batch.
- `max.retries: 30`: Coupled with `retry.backoff.ms`, this enables "Smart Retries"—if a child record (Order) arrives before the parent (Customer), the sink will retry until the constraint is satisfied.
- `retry.backoff.ms: 2000`: Sets the wait time between retries to give the parent record time to arrive and be processed by another task.
- `errors.tolerance: all`: Prevents the connector from failing completely if a record remains unprocessable after all retries.

---

### Use Case 5: Partial LOB Updates (Custom SMT)

Handles the complex scenario where a LOB column (CLOB/BLOB) is not part of an update operation. In Oracle XStream, if a LOB is not modified, it is not included in the LCUR (LCR). This leads to challenges in downstream replication.

- **Mechanism**: Uses a **Custom SMT** (`RemoveAttributeWithValue`) to filter out placeholder values injected by the Source Connector.
- **Oracle Action**: Performs a "Partial Update" on a row containing a CLOB, modifying only a numeric column.
- **Table**: `DATA_TYPES_TEST` (Update `NUMBER_COL` for `ID = 2`).

```bash
./bin/09_run_use_case_5.sh
```

- **Verification**:
  The script verifies that `NUMBER_COL` is updated in Postgres while the existing `CLOB_COL` value remains untouched (not overwritten by placeholders or nulls).

#### 🛡️ The Partial LOB Update Challenge

When an `UPDATE` occurs in Oracle that does **not** include a LOB column, the XStream API does not provide the LOB value in the change record. This creates a dilemma for replication:
1. **Source Connector**: If `lob.enabled=true`, the connector must emit *something* for the missing LOB. By default, it uses an `unavailable.value.placeholder`.
2. **Sink Connector**: Without intervention, the Sink would write this placeholder (e.g., `__cflt_unavailable_value`) into the destination database, corrupting the existing data.
3. **Requirement**: We need the Sink to **ignore** the field entirely if it contains the placeholder, allowing the database to keep its current value.

#### 💡 The Solution: Custom SMT + Connector Properties

We solve this using a multi-layered approach:

**1. Source Configuration (`lob.enabled` & `placeholder`)**:
- `lob.enabled: true`: Ensures LOBs are handled by the connector.
- `unavailable.value.placeholder: "__cflt_unavailable_value"`: Defines a unique string that signaling "this LOB was not part of the update".

**2. Custom SMT (`RemoveAttributeWithValue`)**:
- We developed a Java-based SMT that inspects records (both Schemaless and Schema-based).
- The SMT is automatically built as an uber-JAR by the `./00_start_local_environment.sh` script.
- If a field's value matches the `target.value` configuration, the SMT **removes the field** from the record before it reaches the Sink.

**3. Sink Configuration (`pk.mode: record_key`)**:
- Because the field is removed from the record, the JDBC Sink's `UPDATE` statement simply omits that column, preserving the existing data in Postgres.

#### 🔑 Use Case 5: Key Connector Parameters

**Source Connector:**
- `lob.enabled: true`
- `unavailable.value.placeholder: __cflt_unavailable_value`

**Sink Connector:**
- `transforms: ...,RemovePlaceholder`
- `transforms.RemovePlaceholder.type: io.confluent.csta.smt.RemoveAttributeWithValue`
- `transforms.RemovePlaceholder.target.values: __cflt_unavailable_value,X19jZmx0X3VuYXZhaWxhYmxlX3ZhbHVl`

---

## 🧹 Cleanup

To completely reset the environment (including wiping the Oracle database volume):

```bash
docker compose down -v
```
