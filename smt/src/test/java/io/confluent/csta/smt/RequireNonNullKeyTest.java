package io.confluent.csta.smt;

import org.apache.kafka.connect.data.Schema;
import org.apache.kafka.connect.data.SchemaBuilder;
import org.apache.kafka.connect.data.Struct;
import org.apache.kafka.connect.errors.DataException;
import org.apache.kafka.connect.source.SourceRecord;
import org.junit.Before;
import org.junit.Test;

import java.util.Collections;
import java.util.HashMap;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertSame;
import static org.junit.Assert.fail;

public class RequireNonNullKeyTest {

    private RequireNonNullKey<SourceRecord> xform;

    @Before
    public void setup() {
        xform = new RequireNonNullKey<>();
        xform.configure(Collections.emptyMap());
    }

    @Test
    public void testNullKeyThrows() {
        SourceRecord record = new SourceRecord(null, null, "test", null, null, null, new HashMap<>());
        try {
            xform.apply(record);
            fail("Expected a DataException for a null key");
        } catch (DataException e) {
            // expected
        }
    }

    @Test
    public void testPrimitiveKeyPassesThrough() {
        SourceRecord record = new SourceRecord(null, null, "test", Schema.STRING_SCHEMA, "AD_VP", null,
                new HashMap<>());
        SourceRecord transformed = xform.apply(record);
        assertSame(record, transformed);
    }

    @Test
    public void testStructKeyPassesThrough() {
        Schema keySchema = SchemaBuilder.struct().field("ID", Schema.INT32_SCHEMA).build();
        Struct key = new Struct(keySchema).put("ID", 1);

        SourceRecord record = new SourceRecord(null, null, "test", keySchema, key, null, new HashMap<>());
        SourceRecord transformed = xform.apply(record);
        assertEquals(key, transformed.key());
    }
}
