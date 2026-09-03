package io.confluent.csta.smt;

import org.apache.kafka.common.config.ConfigDef;
import org.apache.kafka.connect.connector.ConnectRecord;
import org.apache.kafka.connect.errors.DataException;
import org.apache.kafka.connect.transforms.Transformation;

import java.util.Map;

/**
 * Single Message Transform (SMT) that rejects any record whose Kafka message
 * key is null.
 *
 * Kafka Connect's errors.tolerance / dead-letter-queue machinery only covers
 * the converter and transformation stages of a sink task -- NOT exceptions
 * thrown while delivering a record to the connector (SinkTask.put()). A JDBC
 * sink configured with delete.enabled=true and pk.mode=record_key requires a
 * non-null key and throws an unrecoverable ConnectException inside put()
 * when a record has none; errors.tolerance never sees that exception, so the
 * task crashes outright and the offending record is neither written nor
 * routed to the DLQ.
 *
 * Chaining this SMT ahead of the sink's other transforms moves the failure
 * into the transformation stage, which errors.tolerance=all DOES cover --
 * routing the null-key record to the dead letter queue instead of crashing
 * the task. It is a guard rail, not a fix for the root cause: a table should
 * still get a primary key, a unique index, or a message.key.columns entry.
 */
public class RequireNonNullKey<R extends ConnectRecord<R>> implements Transformation<R> {

    public static final String OVERVIEW_DOC = "Fails the record (routed to the DLQ under "
            + "errors.tolerance=all) if its Kafka message key is null.";

    private static final ConfigDef CONFIG_DEF = new ConfigDef(Collections.emptyList());

    @Override
    public void configure(Map<String, ?> configs) {
        // No configuration needed.
    }

    @Override
    public R apply(R record) {
        if (record == null) {
            return null;
        }

        if (record.key() == null) {
            throw new DataException(
                    "Record at topic='" + record.topic() + "', partition=" + record.kafkaPartition()
                            + " has a null key. A JDBC sink with delete.enabled=true and "
                            + "pk.mode=record_key would crash inside put() on this record -- give the "
                            + "source table a primary key, a unique index, or a message.key.columns "
                            + "entry.");
        }
        return record;
    }

    @Override
    public ConfigDef config() {
        return CONFIG_DEF;
    }

    @Override
    public void close() {
    }
}
