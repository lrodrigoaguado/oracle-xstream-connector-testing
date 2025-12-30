# 🚀 Oracle XStream CDC Connector Testing Environment

A comprehensive testing environment for the **Confluent Oracle XStream CDC Source Connector**, enabling real-time change data capture (CDC) from Oracle Database to Apache Kafka.

## 📋 Disclaimer

The code and/or instructions here available are NOT intended for production usage. It's only meant to serve as an example or reference and does not replace the need to follow actual and official documentation of referenced products.

## 📋 Overview

The code and/or instructions here available are NOT intended for production usage. It's only meant to serve as an example or reference and does not replace the need to follow actual and official documentation of referenced products.

---

## 🏗️ Pre-requisites: Installation & Deployment

This section covers the end-to-end setup of the environment, comprising the AWS-hosted Oracle Database and the local Confluent Platform.

### 0.1 Deploy Oracle Database (AWS)
Navigate to the `tf/` directory and use Terraform to provision the Oracle XE 21c instance on AWS EC2.

```bash
terraform -chdir=tf init
terraform -chdir=tf apply --auto-approve
```
> **Note**: This process creates an EC2 instance, configures networking, and starts an Oracle XE container with XStream Out configured.

After completion, note the outputs:
```bash
terraform -chdir=tf output oracle_vm_db_details
terraform -chdir=tf output oracle_xstream_connector
```

The deployment of the database will take several minutes. You can check the status by logging into the EC2 instance, and running:

```bash
tail -f /var/log/script_debug.log
```

Starting and configuring the Oracle database may take several minutes.

**Verify Oracle is healthy:**

```bash
# Check container health
docker inspect oracle-xe | grep -A 5 Health

# Connect to Oracle
docker exec -it oracle-xe sqlplus system/Welcome1@localhost:1521/XEPDB1
```

> [!IMPORTANT]
> The Oracle database is configured with:
> - **SYS password**: `Welcome1`
> - **XStream user**: `c##cfltuser` / `My_RandomPass192837465`
> - **Test schema**: `TESTING` (password: `password`)
> - **Outbound server**: `XOUT`

---

## 🐳 Step 2: Start Local Confluent Platform

### 2.1 Start the Cluster

```bash
# Start all services
docker-compose up -d --build. --force-recreate

# Monitor startup
docker-compose logs -f
```

The Connect image requires Oracle Instant Client libraries, and so uses a modified version of the original cp-connect base image. This Dockerfile:
- Starts from `confluentinc/cp-server-connect:7.9.5`
- Installs `libaio` (required by Oracle client)
- Installs Oracle Instant Client 23.26.0.0

**Startup sequence:**
1. Brokers initialize in KRaft mode (combined broker/controller)
2. Schema Registry connects to brokers
3. Connect worker starts and installs Oracle XStream connector
4. Control Center, Prometheus, and Alertmanager start

> **⏱️ Startup Time**: Approximately 2-3 minutes

### 2.3 Verify Cluster Health

### 0.2 Start Confluent Platform (Local)
Start the local Kafka ecosystem (Brokers, Connect, Schema Registry, Control Center) using Docker Compose.

```bash
docker-compose up -d --build --force-recreate
```
> After some moments you will be able to access the Control Center at `http://localhost:9021` and verify that all services are healthy.

### 0.3 Deploy the Connector
Instantiate the Oracle XStream Source Connector using the details from the Terraform output.

1.  Generate your config file from the template `etc/xstream-source-connector.json.template` -> `etc/xstream-source-connector.json`.
2.  Fill in the `database.hostname`, `database.port`, and other details from step 1.
3.  Deploy via REST API:

```bash
curl -X POST http://localhost:8083/connectors \
  -H "Content-Type: application/json" \
  -d @etc/xstream-source-connector.json
```

---

## 🔌 Step 3: Deploy and Configure the Connector

### 3.1 Update Connector Configuration

Use the `xstream-source-connector.json.template` to generate a `etc/xstream-connector-config.json` file with your Oracle database details:

```json
{
  "name": "OracleXStreamSourceConnector",
  "config": {
    "name": "OracleXStreamSourceConnector",
    "connector.class": "io.confluent.connect.oracle.xstream.cdc.OracleXStreamSourceConnector",
    "tasks.max": "1",
    "key.converter": "io.confluent.connect.avro.AvroConverter",
    "key.converter.schema.registry.url": "http://schema-registry:8081",
    "value.converter": "io.confluent.connect.avro.AvroConverter",
    "value.converter.schema.registry.url": "http://schema-registry:8081",
    "errors.log.enable": "true",
    "errors.log.include.messages": "true",
    "database.hostname": "XXXXX",
    "database.port": "YYYY",
    "database.user": "c##cfltuser",
    "database.password": "My_RandomPass192837465",
    "database.dbname": "XE",
    "database.service.name": "XE",
    "database.pdb.name": "XEPDB1",
    "database.out.server.name": "XOUT",
    "database.processor.licenses": "1",
    "decimal.handling.mode": "double",
    "topic.prefix": "xstream",
    "table.include.list": "C##CFLTUSER[.].*",
    "schema.history.internal.kafka.topic": "__orcl-schema-changes.XEPDB1",
    "schema.history.internal.kafka.bootstrap.servers": "broker1:29092,broker2:29092,broker3:29092",
    "schema.history.internal.skip.unparseable.ddl": "true",
    "schema.history.internal.store.only.captured.tables.ddl": "true",
    "skipped.operations": "none",
    "time.precision.mode" : "connect",
    "transforms": "flatten",
    "transforms.flatten.type": "io.debezium.transforms.ExtractNewRecordState",
    "transforms.flatten.drop.tombstones": "false",
    "transforms.flatten.delete.handling.mode": "none",
    "transforms.flatten.delete.tombstone.handling.mode": "tombstone",
    "transforms.flatten.add.fields.prefix": "db_"
  }
}
```
or simply by using a DB management tool, such as DBeaver and connecting remotely to the Oracle XE instance.
</details>

And deploy the JDBC Sink connector that will replicate the database into the local Postgres instance:

```bash
curl -X POST http://localhost:8083/connectors \
  -H "Content-Type: application/json" \
  -d @etc/xstream-source-connector.json
```

*Verification*: Check the topic `xstream.C__CFLTUSER.EMPLOYEES` in Control Center. You should see the initial records. And you can use the same DB management tool to connect to the local Postgres instance and verify that the data has been replicated using the following connection data:

```bash
host: localhost
port: 5432
database: test-connector
user: test-connector
password: test-connector
```

### 1.2 DML Operations (Update & Delete)
Test that standard row modifications are captured.

1.  **Update**: Run `scripts/use_case_1/01_update.sql`
2.  **Delete**: Run `scripts/use_case_1/02_delete.sql`

```bash
docker logs connect | grep -i oracle
```

And now deploy the sink connectors that will write the data to the Postgres database:

```bash
# Deploy connector via REST API
curl -X POST http://localhost:8083/connectors \
  -H "Content-Type: application/json" \
  -d @etc/postgres/jdbc-sink-connector.json
```

```bash
# Deploy connector via REST API
curl -X POST http://localhost:8083/connectors \
  -H "Content-Type: application/json" \
  -d @etc/postgres/jdbc-sink-blob-connector.json
```

**In Control Center:**

1. Navigate to **Connect** → **connect-default**
2. Click on **OracleXStreamSourceConnector**
3. View **Status**, **Configuration**, and **Tasks**

> [!WARNING]
> If the connector shows `FAILED` state, common issues include:
> - Incorrect database hostname/credentials
> - Network connectivity issues (check security groups)
> - XStream server not properly configured
> - Missing Oracle client libraries

---

## 📊 Step 4: Test Data Flow

### 4.1 Create a Test Table

Connect to Oracle and create a table in the `C##CFLTUSER` schema. For that, you can log into the EC2 instance with:

```bash
# SSH to EC2 instance
ssh -i ~/.ssh/your-key.pem ec2-user@<EC2_PUBLIC_IP>

# Connect to Oracle as TESTING user
docker exec -it oracle-xe sqlplus C##CFLTUSER/My_RandomPass192837465@localhost:1521/XEPDB1
```

or use a Database Manager of your choice (such as DBeaver) and connect remotely.

```sql
-- Create a sample table
CREATE TABLE C##CFLTUSER.EMPLOYEES (
    EMPLOYEE_ID NUMBER(6) PRIMARY KEY,
    FIRST_NAME VARCHAR2(50),
    LAST_NAME VARCHAR2(50),
    EMAIL VARCHAR2(100),
    HIRE_DATE DATE,
    SALARY NUMBER(8,2),
    DEPARTMENT VARCHAR2(50)
);
```

### 4.2 Insert Test Data

### 1.3 Schema Evolution (DDL)
Test the connector's ability to handle schema changes.

1.  **Add Column**: Run `scripts/use_case_1/03_schema_changes.sql`

*Verification*: Check the `__orcl-schema-changes` topic and subsequent messages in the main topic to see the new `PHONE_NUMBER` field.

### 1.4 Complex Data Types & Limitations (XMLType, LONG)
This scenario tests `CLOB`, `BLOB`, `XMLType`, and `LONG` data types.
**Run Script**: `scripts/use_case_1/04_complex_types.sql`

#### 🔑 Key Configurations
- **Source**: Standard configuration.
- **Oracle DB**: Includes a `BEFORE INSERT OR UPDATE` trigger to copy `XMLTYPE` to `CLOB`.
- **Sink**: Standard JDBC Sink with `pk.mode: record_value` (default for PK tables).

#### ⚠️ Important Caveats regarding Oracle Technologies
Please note that the following limitations are inherent to the **Oracle Database** and **Oracle XStream API** technologies, not the Confluent Connector itself.

> [!WARNING]
> **LONG Columns**:
> * **Limitation**: Oracle Database **does not support Supplemental Logging for `LONG` columns**.
> * **Impact**: Since XStream relies on redo logs and supplemental logging to construct Logical Change Records (LCRs), it is technically impossible for the capture process to retrieve the `LONG` value for every change.
> * **Result**: The `LONG_COL` field will appear in the Kafka message but will likely be null or empty.
> * **Recommendation**: Convert legacy `LONG` columns to `CLOB` or `NCLOB` in your database design.

> [!TIP]
> **XMLType Columns**:
> * **Limitation**: Native XStream capture of `XMLTYPE` can be inconsistent depending on storage (Binary XML vs CLOB) and internal filtering.
> * **Workaround Implemented**: The script `04_complex_types.sql` creates a **Trigger** (`trg_data_types_test`) that automatically copies the `XMLTYPE` column into a `CLOB` column (`XML_COL_CLOB`) whenever a row is changed.
> * **Result**: You will see your XML data reliably captured in the `XML_COL_CLOB` field in Kafka.

---

## 🧪 Use Case 2: No-PK with Unique Index (Auto-Key Derivation)

This use case demonstrates how the connector can automatically derive the Kafka key from an Oracle **Unique Index** when a Primary Key is missing. This is the recommended approach when you can modify the database schema.

### 2.1 Overview
The connector identifies the Unique Index and uses it to populate the Kafka record key. This allows for full CDC support, including **Deletes**, without any SMT configuration.

### 2.2 Setup & Data
1. **Table**: `DEPARTMENTS` (No PK, but with a Unique Index) already created in the `scripts/setup/01_create_tables.sql`.
2. **Operations**: `scripts/use_case_2/01_operations.sql` (Upserts)

COMMIT;
```

1. **Deletes:** `scripts/use_case_2/02_deletes.sql` (Deletes).

### 2.3 🔑 Key Configurations
- **Source**: No `message.key.columns` needed for this table; the connector derives the key from the unique index.
- **Sink**: `pk.mode: record_key` and `delete.enabled: true`.

---

## 🧪 Use Case 3: No-PK and no Unique Index (with Deletes)

This use case addresses the limitation of Use Case 2 by extracting a Key from the record value at the source, allowing full CDC support (including deletes).

### 3.1 Overview

To support deletes for tables without Primary Keys, we use the connector's native **Key Extraction** on a `NOT NULL` column in the database to produce a clean, non-nullable key.

> [!IMPORTANT]
> **Schema Tip**: To avoid Avro "union" wrappers (like `{"string": "..."}`) in your Kafka keys, ensure the source column is defined as **`NOT NULL`** in Oracle.

### 3.2 🔑 Key Configurations
- **Source**:
  - `message.key.columns`: Defines `JOB_ID` as the key.
- **Sink**: `pk.mode: record_key` and `delete.enabled: true`.

### 3.3 Setup & Data

1. **Table**: `JOBS` (No PK) already created in the `scripts/setup/01_create_tables.sql`.
2. **Operations**: `scripts/use_case_3/01_operations.sql`.

You should be able to see four rows in the `JOBS` table in Postgres, one of them having `JOB_ID = 'AD_VP'` and `MAX_SALARY = 35000`.

1. **Deletes**: `scripts/use_case_3/02_deletes.sql` (Deletes).

Now the row with `JOB_ID = 'ST_CLERK'` should dissapear from Postgres.

### 3.4 🔑 Key Configurations
The process relies on the capability of the Source connector to generate a Key for the messages from the message values using the `message.key.columns` configuration.

---

## 🧪 Use Case 4: Referential Integrity (Smart Retries & Deferrable Constraints)

This use case demonstrates how to handle complex relationships between tables (Foreign Keys) to ensure data consistency in the target system, even when updates to different tables arrive asynchronously in Kafka.

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

### 4.2 Setup & Data

1. **Oracle Table**: `CUSTOMERS` and `ORDERS` (created in `scripts/setup/01_create_tables.sql`).
2. **Postgres Table**: Run `scripts/setup/03_create_postgres_tables.sql` in your local Postgres.
3. **Operations**: `scripts/use_case_4/01_operations.sql` (Inserts/Updates) and `scripts/use_case_4/02_deletes.sql` (Deletes).

### 4.3 🔑 Key Configurations

The effectiveness of this use case relies on how the following properties interact to manage the "gap" between parent and child availability:

- **`tasks.max: 4`**: By increasing the number of tasks, we ensure that if one task get stuck retrying an `ORDERS` record (waiting for a FK), other tasks are free to continue pulling `CUSTOMERS` records from Kafka. Without multiple tasks, a single retry loop could block the entire pipeline.
- **`max.retries: 30` & `retry.backoff.ms: 2000`**: Together, these properties define a **60-second recovery window** (30 retries * 2s). This is the maximum time a "child" record will wait for its "parent" to arrive in Postgres before giving up.
- **`errors.tolerance: all`**: This is a safety net. It tells the connector "if a record still fails after all 30 retries, do not stop the connector; instead, follow the error handling policy (the DLQ)".
- **`errors.deadletterqueue.topic.name: SINK_DLQ`**: Any record that exceeds the 60-second retry window is routed here. This allows you to inspect the failed data (e.g., an order for a customer that was never created in the source) and manually reprocess it later without interrupting the main data flow.

## 🧹 Cleanup

```bash
docker compose down -v
terraform -chdir=tf destroy --auto-approve
```
