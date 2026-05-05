package io.confluent.csta.smt;

import org.apache.kafka.common.cache.Cache;
import org.apache.kafka.common.cache.LRUCache;
import org.apache.kafka.common.cache.SynchronizedCache;
import org.apache.kafka.common.config.AbstractConfig;
import org.apache.kafka.common.config.ConfigDef;
import org.apache.kafka.connect.connector.ConnectRecord;
import org.apache.kafka.connect.data.Field;
import org.apache.kafka.connect.data.Schema;
import org.apache.kafka.connect.data.SchemaBuilder;
import org.apache.kafka.connect.data.Struct;
import org.apache.kafka.connect.transforms.Transformation;

import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Iterator;
import java.util.Map;
import java.util.Set;

/**
 * Single Message Transform (SMT) that removes attributes from a record value
 * if their value matches any of the configured target strings.
 *
 * This is particularly useful for handling partial LOB updates where
 * placeholders
 * like '__cflt_unavailable_value' should be removed before reaching the sink
 * to preserve existing data.
 */
public class RemoveAttributeWithValue<R extends ConnectRecord<R>> implements Transformation<R> {

    public static final String OVERVIEW_DOC = "Removes attributes from the record value if their value matches a configured string.";

    public static final String TARGET_VALUES_CONFIG = "target.values";
    public static final String TARGET_VALUES_DOC = "Comma-separated list of values to look for. Attributes with these values will be removed.";

    private static final ConfigDef CONFIG_DEF = new ConfigDef()
            .define(TARGET_VALUES_CONFIG, ConfigDef.Type.LIST, ConfigDef.Importance.HIGH, TARGET_VALUES_DOC);

    private Set<String> targetValues;

    @Override
    public void configure(Map<String, ?> props) {
        final AbstractConfig config = new AbstractConfig(CONFIG_DEF, props);
        // Use a HashSet for O(1) matching during record processing
        targetValues = new HashSet<>(config.getList(TARGET_VALUES_CONFIG));
    }

    @Override
    public R apply(R record) {
        if (record.value() == null) {
            return record;
        }

        if (record.valueSchema() == null) {
            return applySchemaless(record);
        } else {
            return applyWithSchema(record);
        }
    }

    private R applySchemaless(R record) {
        if (!(record.value() instanceof Map)) {
            return record;
        }

        @SuppressWarnings("unchecked")
        final Map<String, Object> value = (Map<String, Object>) record.value();
        final Map<String, Object> updatedValue = new HashMap<>(value);
        final Iterator<Map.Entry<String, Object>> iterator = updatedValue.entrySet().iterator();

        boolean updated = false;
        while (iterator.hasNext()) {
            Map.Entry<String, Object> entry = iterator.next();
            Object val = entry.getValue();
            if (val != null && targetValues.contains(val.toString())) {
                iterator.remove();
                updated = true;
            }
        }

        if (!updated) {
            return record;
        }

        return record.newRecord(
                record.topic(),
                record.kafkaPartition(),
                record.keySchema(),
                record.key(),
                null,
                updatedValue,
                record.timestamp());
    }

    private R applyWithSchema(R record) {
        final Struct value = (Struct) record.value();
        final Schema schema = record.valueSchema();

        // We must build the new schema for every record because the fields to remove
        // depend on the values of that specific record.
        final SchemaBuilder builder = SchemaBuilder.struct();
        copySchemaMetadata(schema, builder);

        boolean fieldsRemoved = false;
        for (Field field : schema.fields()) {
            Object fieldValue = value.get(field);
            if (shouldRemoveField(fieldValue)) {
                fieldsRemoved = true;
            } else {
                builder.field(field.name(), field.schema());
            }
        }

        if (!fieldsRemoved) {
            return record;
        }

        final Schema updatedSchema = builder.build();
        final Struct newValue = new Struct(updatedSchema);
        for (Field field : updatedSchema.fields()) {
            newValue.put(field, value.get(field.name()));
        }

        return record.newRecord(
                record.topic(),
                record.kafkaPartition(),
                record.keySchema(),
                record.key(),
                updatedSchema,
                newValue,
                record.timestamp());
    }

    /**
     * Helper to determine if a field value matches any target values.
     */
    private boolean shouldRemoveField(Object value) {
        if (value == null)
            return false;
        // Fast path for String values, common for placeholders
        if (value instanceof String) {
            return targetValues.contains((String) value);
        }
        // Connect BYTES schema may surface as byte[] (raw) or ByteBuffer (Avro
        // converter). Decode as UTF-8 so the placeholder bytes for an
        // unavailable BLOB / RAW column can be matched against the same target
        // strings used for text LOBs.
        if (value instanceof byte[]) {
            return targetValues.contains(new String((byte[]) value, StandardCharsets.UTF_8));
        }
        if (value instanceof ByteBuffer) {
            // duplicate() so we don't move the position of the original buffer
            ByteBuffer buf = ((ByteBuffer) value).duplicate();
            byte[] bytes = new byte[buf.remaining()];
            buf.get(bytes);
            return targetValues.contains(new String(bytes, StandardCharsets.UTF_8));
        }
        return targetValues.contains(value.toString());
    }

    /**
     * Copies basic metadata (name, version, doc, params) from source schema to
     * builder.
     */
    private void copySchemaMetadata(Schema source, SchemaBuilder builder) {
        if (source.name() != null)
            builder.name(source.name());
        if (source.version() != null)
            builder.version(source.version());
        if (source.doc() != null)
            builder.doc(source.doc());
        if (source.parameters() != null)
            builder.parameters(source.parameters());
    }

    @Override
    public ConfigDef config() {
        return CONFIG_DEF;
    }

    @Override
    public void close() {
    }
}
