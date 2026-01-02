#!/bin/bash

# Configuration
CONNECTOR_NAME="JdbcSinkConnector"
TEMPLATE_FILE="etc/postgres/jdbc-sink-connector.json.template"
CONFIG_FILE="etc/postgres/jdbc-sink-connector.json"
CONNECT_API="http://localhost:8083"

echo "🚀 Starting Jdbc Sink Connector deployment..."

# Prepare Configuration File
echo "🔧 Regenerating $CONFIG_FILE from template..."
if [[ ! -f "$TEMPLATE_FILE" ]]; then
    echo "❌ Error: Template file $TEMPLATE_FILE not found."
    exit 1
fi

cp "$TEMPLATE_FILE" "$CONFIG_FILE"
echo "✅ Configuration file updated."

# Deploy Connector
echo "🚢 Deploying connector '$CONNECTOR_NAME'..."

# Extract only the 'config' part from the JSON file for the PUT body
SINK_CONFIG=$(jq '.config' "$CONFIG_FILE")

HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X PUT -H "Content-Type: application/json" -d "$SINK_CONFIG" "$CONNECT_API/connectors/$CONNECTOR_NAME/config")

if [[ "$HTTP_STATUS" -eq 200 || "$HTTP_STATUS" -eq 201 ]]; then
    echo "✨ Connector '$CONNECTOR_NAME' deployed successfully (HTTP $HTTP_STATUS)."
else
    echo "❌ Error: Failed to deploy connector. HTTP Status: $HTTP_STATUS"
    exit 1
fi

echo "🏁 Deployment complete."
