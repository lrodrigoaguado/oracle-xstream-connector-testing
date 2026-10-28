#!/bin/bash
set -e
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONNECT_URL="http://localhost:8083"
SOURCE_CONNECTOR_CONFIG_FILE="$PROJECT_DIR/etc/connectors/source-connector.json"
SINK_CONNECTOR_CONFIG_FILE="$PROJECT_DIR/etc/connectors/sink-connector.json"

echo "⏳ Waiting for Kafka Connect to be ready..."
while [ $(curl -s -o /dev/null -w %{http_code} $CONNECT_URL/) -ne 200 ]; do
  echo -n "."
  sleep 5
done
echo " Ready!"

# Pre-create the change-event topics (same settings as topic.creation.default.* in the source
# connector). Otherwise each topic is created by the first record written to it, and the sink
# (subscribed through topics.regex) only discovers it later, through a consumer-group rebalance
# in the middle of a use case. A parent/child pair such as CUSTOMERS/ORDERS could then be
# fetched in separate polls, and the sink cannot retry its way out of that: Connect pauses the
# consumer while it redelivers a failed batch, so the missing parent is never fetched.
echo "----------------------------------------------------------------"
echo "🗂️  Creating the change-event topics (single partition, so the sink discovers them up front)..."
for table in EMPLOYEES DEPARTMENTS JOBS AUDIT_LOG CUSTOMERS ORDERS DATA_TYPES_TEST CLOB_TEST; do
    docker exec broker1 kafka-topics --bootstrap-server broker1:29092 --create --if-not-exists \
        --topic "xstream.DEMO.${table}" --partitions 1 --replication-factor 3
done

echo "----------------------------------------------------------------"
echo "📡 Creating the source connector's signal topic (single partition, as required)..."
docker exec broker1 kafka-topics --bootstrap-server broker1:29092 --create --if-not-exists \
    --topic xstream-signals --partitions 1 --replication-factor 3

echo "----------------------------------------------------------------"
echo "🚀 Deploying Oracle XStream Source Connector..."
CONNECTOR_CONFIG=$(jq '.config' "$SOURCE_CONNECTOR_CONFIG_FILE")
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X PUT -H "Content-Type: application/json" \
              -d "$CONNECTOR_CONFIG"  \
              $CONNECT_URL/connectors/OracleXStreamSourceConnector/config)
if [[ "$HTTP_STATUS" -eq 200 || "$HTTP_STATUS" -eq 201 ]]; then
    echo "✨ Connector 'OracleXStreamSourceConnector' deployed successfully (HTTP $HTTP_STATUS)."
else
    echo "❌ Error: Failed to deploy connector. HTTP Status: $HTTP_STATUS"
    exit 1
fi

echo "----------------------------------------------------------------"
echo "🚀 Deploying JDBC Sink Connector..."
CONNECTOR_CONFIG=$(jq '.config' "$SINK_CONNECTOR_CONFIG_FILE")
HTTP_STATUS=$(curl  -s -o /dev/null -w "%{http_code}" -X PUT -H "Content-Type: application/json" \
              -d "$CONNECTOR_CONFIG"  \
              $CONNECT_URL/connectors/JdbcSinkConnector/config)
if [[ "$HTTP_STATUS" -eq 200 || "$HTTP_STATUS" -eq 201 ]]; then
    echo "✨ Connector 'JdbcSinkConnector' deployed successfully (HTTP $HTTP_STATUS)."
else
    echo "❌ Error: Failed to deploy connector. HTTP Status: $HTTP_STATUS"
    exit 1
fi

echo "----------------------------------------------------------------"
echo "✅ Connectors Deployed"
