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
