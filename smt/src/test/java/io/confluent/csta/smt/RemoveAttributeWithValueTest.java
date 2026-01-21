package io.confluent.csta.smt;

import org.apache.kafka.connect.data.Schema;
import org.apache.kafka.connect.data.SchemaBuilder;
import org.apache.kafka.connect.data.Struct;
import org.apache.kafka.connect.source.SourceRecord;
import org.junit.Before;
import org.junit.Test;

import java.util.Collections;
import java.util.HashMap;
import java.util.Map;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

public class RemoveAttributeWithValueTest {

    private RemoveAttributeWithValue<SourceRecord> xform;

    @Before
    public void setup() {
        final Map<String, Object> props = new HashMap<>();
        props.put("target.values", java.util.Collections.singletonList("DELETE_ME"));

        xform = new RemoveAttributeWithValue<>();
        xform.configure(props);
    }

    // --- Schemaless (Map) Tests ---

    @Test
    public void testSchemalessNoMatch() {
        Map<String, Object> value = new HashMap<>();
        value.put("key1", "value1");
        value.put("key2", "value2");

        SourceRecord record = new SourceRecord(null, null, "test", null, null, null, value);
        SourceRecord transformed = xform.apply(record);

        Map<String, Object> updatedValue = (Map<String, Object>) transformed.value();
        assertEquals(2, updatedValue.size());
        assertEquals("value1", updatedValue.get("key1"));
        assertEquals("value2", updatedValue.get("key2"));
    }

    @Test
    public void testSchemalessSingleMatch() {
        Map<String, Object> value = new HashMap<>();
        value.put("keep", "value1");
        value.put("remove", "DELETE_ME");

        SourceRecord record = new SourceRecord(null, null, "test", null, null, null, value);
        SourceRecord transformed = xform.apply(record);

        Map<String, Object> updatedValue = (Map<String, Object>) transformed.value();
        assertEquals(1, updatedValue.size());
        assertEquals("value1", updatedValue.get("keep"));
        assertTrue(!updatedValue.containsKey("remove"));
    }

    @Test
    public void testSchemalessMultipleMatches() {
        Map<String, Object> value = new HashMap<>();
        value.put("keep", "value1");
        value.put("remove1", "DELETE_ME");
        value.put("remove2", "DELETE_ME");

        SourceRecord record = new SourceRecord(null, null, "test", null, null, null, value);
        SourceRecord transformed = xform.apply(record);

        Map<String, Object> updatedValue = (Map<String, Object>) transformed.value();
        assertEquals(1, updatedValue.size());
        assertEquals("value1", updatedValue.get("keep"));
        assertTrue(!updatedValue.containsKey("remove1"));
        assertTrue(!updatedValue.containsKey("remove2"));
    }

    // --- Schema-based (Struct) Tests ---

    @Test
    public void testWithSchemaNoMatch() {
        Schema schema = SchemaBuilder.struct()
                .field("key1", Schema.STRING_SCHEMA)
                .field("key2", Schema.STRING_SCHEMA)
                .build();

        Struct value = new Struct(schema);
        value.put("key1", "value1");
        value.put("key2", "value2");

        SourceRecord record = new SourceRecord(null, null, "test", null, schema, value);
        SourceRecord transformed = xform.apply(record);

        Struct updatedValue = (Struct) transformed.value();
        Schema updatedSchema = transformed.valueSchema();

        assertEquals(2, updatedSchema.fields().size());
        assertEquals("value1", updatedValue.get("key1"));
        assertEquals("value2", updatedValue.get("key2"));
    }

    @Test
    public void testWithSchemaSingleMatch() {
        Schema schema = SchemaBuilder.struct()
                .field("keep", Schema.STRING_SCHEMA)
                .field("remove", Schema.STRING_SCHEMA)
                .build();

        Struct value = new Struct(schema);
        value.put("keep", "value1");
        value.put("remove", "DELETE_ME");

        SourceRecord record = new SourceRecord(null, null, "test", null, schema, value);
        SourceRecord transformed = xform.apply(record);

        Struct updatedValue = (Struct) transformed.value();
        Schema updatedSchema = transformed.valueSchema();

        assertEquals(1, updatedSchema.fields().size());
        assertNull(updatedSchema.field("remove"));
        assertEquals("value1", updatedValue.get("keep"));
    }

    @Test
    public void testWithSchemaMultipleMatches() {
        Schema schema = SchemaBuilder.struct()
                .field("keep", Schema.STRING_SCHEMA)
                .field("remove1", Schema.STRING_SCHEMA)
                .field("remove2", Schema.STRING_SCHEMA)
                .build();

        Struct value = new Struct(schema);
        value.put("keep", "value1");
        value.put("remove1", "DELETE_ME");
        value.put("remove2", "DELETE_ME");

        SourceRecord record = new SourceRecord(null, null, "test", null, schema, value);
        SourceRecord transformed = xform.apply(record);

        Struct updatedValue = (Struct) transformed.value();
        Schema updatedSchema = transformed.valueSchema();

        assertEquals(1, updatedSchema.fields().size());
        assertNull(updatedSchema.field("remove1"));
        assertNull(updatedSchema.field("remove2"));
        assertEquals("value1", updatedValue.get("keep"));
    }
}
