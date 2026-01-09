# 🚀 Oracle XStream CDC Connector Testing Environment

A comprehensive testing environment for the **Confluent Oracle XStream CDC Source Connector**, enabling real-time change data capture (CDC) from Oracle Database to Apache Kafka.

## 📋 Disclaimer

The code and/or instructions here available are NOT intended for production usage. It's only meant to serve as an example or reference and does not replace the need to follow actual and official documentation of referenced products.

---

## 🏗️ Pre-requisites: Installation & Deployment

This section covers the end-to-end setup of the environment, comprising the AWS-hosted Oracle Database and the local Confluent Platform.

### 0.0 Download Oracle Instant Client

Due to redistribution restrictions, you must manually download the Oracle Instant Client Basic RPM and place it in the `etc/` folder.

1. Download the **Oracle Instant Client Basic (RPM)** for Linux x86-64 (or aarch64 if running on ARM) from the [Oracle Website](https://www.oracle.com/database/technologies/instant-client/downloads.html).

   * Example: `oracle-instantclient-basic-23.26.0.0.0-1.el8.aarch64.rpm`

2. Place the downloaded `.rpm` file in the `etc/` directory of this repository.

### 0.1 Deploy Oracle Database (AWS)

Navigate to the `tf/` directory and use Terraform to provision the Oracle XE 21c instance on AWS EC2.

```bash
terraform -chdir=tf init
terraform -chdir=tf apply --auto-approve
```

> **Note**: This process creates an EC2 instance, configures networking, and starts an Oracle XE container with XStream Out configured.
> Once the Oracle database is deployed in the EC2 instance, the script will output the connection details, which will be used to configure the Oracle XStream Source Connector.
> The configuration of the Oracle XStream Server will still take several minutes. You can check the status by logging into the EC2 instance, and running:

```bash
tail -f /var/log/script_debug.log
```

The installation will have finished when you can read the message `[XSTREAM] Oracle XE with XStream configured successfully` and prepare to be patient as it may take some minutes to deploy and configure everything.

### 0.2 Start Confluent Platform (Local)

Start the local Kafka ecosystem (Brokers, Connect, Schema Registry, Control Center) using the provided start script. This script will automatically detect the Oracle RPM in the `etc/` folder and update the `Dockerfile` accordingly.

```bash
chmod +x start_local_environment.sh
./start_local_environment.sh
```

> After some moments you will be able to access the Control Center at `http://localhost:9021` and verify that all services are healthy.

### 0.3 Deploy the Source Connector

Make sure both the Oracle database is 100% ready and the local environment is working. Then, run the script

```shell
chmod +x deploy_source_connector.sh
./deploy_source_connector.sh
```

to automatically deploy the Oracle XStream Source Connector using the details from the Terraform output.

### 0.4 Deploy the Sink Connector

Run the script

```shell
chmod +x deploy_sink_connector.sh
./deploy_sink_connector.sh
```

to automatically deploy the JDBC Sink connector that will write the changes from the Oracle XStream Source Connector to the local Postgres instance.

---

## 📊 Monitoring & Metadata Fields

For observability and debugging purposes, the connectors are configured to inject three additional metadata columns into every destination table in Postgres.

| Column Name | Type | Origin | Description |
| :--- | :--- | :--- | :--- |
| **`MAQUINA_ID`** | String | Source Connector | Represents the source database identifier (e.g., `source.db`). Helpful in multi-tenant or multi-source architectures. |
| **`SOURCETIMESTAMP`** | Timestamp | Source Connector | The timestamp when the change event occurred in the Oracle database (mapped from `source.ts_ms`). |
| **`SINKTIMESTAMP`** | Timestamp | Sink Connector | The timestamp when the record was processed by the Sink Connector and written to Postgres. |

### 🔧 How to Remove These Fields

If you wish to remove these fields for a production deployment, modify the connector configuration templates in `etc/`:

1. **Remove `MAQUINA_ID` and `SOURCETIMESTAMP`**:
   * Edit `etc/xstream-source-connector.json.template`.
   * Find `transforms.flatten.add.fields`.
   * Remove `source.db:MAQUINA_ID` and `source.ts_ms:SOURCETIMESTAMP`.
   * Remove the `convertTS` transform if `SOURCETIMESTAMP` is removed.

2. **Remove `SINKTIMESTAMP`**:
   * Edit `etc/postgres/jdbc-sink-connector.json.template`.
   * Remove `insertTS` from the `transforms` list.
   * Remove the `transforms.insertTS.*` properties.

---

## 🧪 Use Case 1: Basic Data Flow

This use case validates the core CDC functionality: capturing DML, DDL, and handling complex data types. All scripts for this use case are located in `scripts/setup/` and `scripts/use_case_1/`.

### 1.1 Setup & Initialization

Establish the baseline state by creating the `EMPLOYEES` table and seeding initial data.

1. **Create Table**: Run `scripts/setup/01_create_tables.sql`
2. **Insert Data**: Run `scripts/setup/02_insert_data.sql`

<details>
<summary><b>How to run the SQL scripts</b></summary>
You can run the scripts in the Oracle database by logging into the EC2 instance and then into the Oracle container by running:

```bash
docker exec -it oracle-xe-21c /bin/bash
```

or simply by using a DB management tool, such as DBeaver and connecting remotely to the Oracle XE instance.

</details>

*Verification*: Check the topic `xstream.DEMO.EMPLOYEES` in Control Center. You should see the initial records. And you can use the same DB management tool to connect to the local Postgres instance and verify that the data has been replicated using the following connection data:

```bash
host: localhost
port: 5432
database: test-connector
user: test-connector
password: test-connector
```

### 1.2 DML Operations (Update & Delete)

Test that standard row modifications are captured.

1. **Update**: Run `scripts/use_case_1/01_update.sql`
2. **Delete**: Run `scripts/use_case_1/02_delete.sql`

*Verification*: Observe the *UPDATE* and *DELETE* events in the `EMPLOYEES` topic.

### 1.3 Schema Evolution (DDL)

Test the connector's ability to handle schema changes.

1. **Add Column**: Run `scripts/use_case_1/03_schema_changes.sql`

*Verification*: Check the `__orcl-schema-changes` topic and subsequent messages in the main topic to see the new `PHONE_NUMBER` field.

### 1.4 Complex Data Types & Limitations (XMLType, LONG)

This scenario tests `CLOB`, `BLOB`, `XMLType`, and `LONG` data types.
**Run Script**: `scripts/use_case_1/04_complex_types.sql`

#### 🔑 Key Configurations

| Connector  | Parameter            | Value        | Reason                                                          |
|:---------- |:-------------------- |:------------ |:--------------------------------------------------------------- |
| **Source** | `table.include.list` | `DEMO[.].*`  | Captures all tables in the DEMO schema.                         |
| **Source** | `transforms`         | `flatten`    | Flattens the complex Debezium envelope for simpler consumption. |
| **Sink**   | `pk.mode`            | `record_key` | Uses the message key (derived from PK) for upserts/deletes.     |
| **Sink**   | `delete.enabled`     | `true`       | Allows propagation of DELETE operations using the key.          |

#### ⚠️ Important Caveats regarding Oracle Technologies

Please note that the following limitations are inherent to the **Oracle Database** and **Oracle XStream API** technologies, not the Confluent Connector itself, as stated in the [Oracle Documentation]([XStream Out Restrictions](https://docs.oracle.com/en/database/oracle/oracle-database/19/xstrm/xstream-out-restrictions.html#GUID-DF1C3A6A-E3EF-4AF4-B4E0-7001E63369C6)).

> [!WARNING]
> **LONG Columns**:
>
> * **Limitation**: Oracle Database **does not support Supplemental Logging for `LONG` columns**.
> * **Impact**: Since XStream relies on redo logs and specified logging to construct Logical Change Records (LCRs), it is technically impossible for the capture process to retrieve the `LONG` value for every change.
> * **Result**: The `LONG_COL` field will appear in the Kafka message but will likely be null or empty.
> * **Recommendation**: Convert legacy `LONG` columns to `CLOB` or `NCLOB` in your database design.

> [!TIP]
> **XMLType Columns**:
>
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
   Check that the three rows in the `DEPARTMENTS` Oracle table have been correctly replicated to Postgres. You can also check the messages in the `xstream.C__CFLTUSER.DEPARTMENTS` topic in Control Center and see that they do have a key.
3. **Deletes:** `scripts/use_case_2/02_deletes.sql` (Deletes).

### 2.3 🔑 Key Configurations

| Connector  | Parameter             | Value                                      | Reason                                                                                                                              |
|:---------- |:--------------------- |:------------------------------------------ |:----------------------------------------------------------------------------------------------------------------------------------- |
| **Source** | `message.key.columns` | No reference to DEPARTMENTS table required | **Auto-Detection**: The connector automatically queries `DBA_INDEXES` to find the unique index on `DEPT_ID` and uses it as the key. |
| **Sink**   | `pk.mode`             | `record_key`                               | Essential. Tells the sink to trust the key provided by the source for identifying rows.                                             |

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
3. **Deletes**: `scripts/use_case_3/02_deletes.sql` (Deletes).
   Now the row with `JOB_ID = 'ST_CLERK'` should disappear from Postgres.

### 3.4 🔑 Key Configurations

| Connector  | Parameter             | Value              | Reason                                                                                          |
|:---------- |:--------------------- |:------------------ |:----------------------------------------------------------------------------------------------- |
| **Source** | `message.key.columns` | `DEMO.JOBS:JOB_ID` | Manually forces the connector to use `JOB_ID` as the key, since there is no PK or Unique Index. |
| **Sink**   | `pk.mode`             | `record_key`       | Uses the manual key from the source to identify modify/delete targets.                          |
| **Sink**   | `delete.enabled`      | `true`             | Enables deletes based on the constructed key.                                                   |

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

| Connector  | Parameter                           | Value           | Reason                                                                                      |
|:---------- |:----------------------------------- |:--------------- |:------------------------------------------------------------------------------------------- |
| **Source** | *Standard*                          | *Standard*      | No special config enables this; it relies on Sink behavior.                                 |
| **Sink**   | `tasks.max`                         | `4`             | Allows parallel processing. One task can retry stuck records while others process new data. |
| **Sink**   | `max.retries`                       | `30`            | High retry count to bridge the timing gap between child and parent records.                 |
| **Sink**   | `retry.backoff.ms`                  | `2000`          | Waits 2s between retries (Total window: 30 * 2s = 60s).                                     |
| **Sink**   | `errors.tolerance`                  | `all`           | Prevents the connector from crashing if the retry window is exceeded; sends to DLQ instead. |
| **Sink**   | `errors.deadletterqueue.topic.name` | `JDBC_SINK_DLQ` | Destination for records that fail after all retries (e.g., truly missing parent).           |
| **Sink**   | `batch.size`                        | `1`             | Ensures granular handling of records so a single failure doesn't reject a whole batch.      |

## 🧹 Cleanup

```bash
docker compose down -v
terraform -chdir=tf destroy --auto-approve
```
