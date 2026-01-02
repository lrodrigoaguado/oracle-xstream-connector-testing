#!/bin/bash

# Configuration
CONNECTOR_NAME="OracleXStreamSourceConnector"
TEMPLATE_FILE="etc/xstream-source-connector.json.template"
CONFIG_FILE="etc/xstream-source-connector.json"
CONNECT_API="http://localhost:8083"

echo "🚀 Starting Oracle XStream CDC Source Connector deployment..."

# Retrieve Terraform Outputs
echo "🔍 Extracting Oracle connection details from Terraform..."
if ! terraform -chdir=tf output -json oracle_xstream_connector > /dev/null 2>&1; then
    echo "❌ Error: Failed to retrieve Terraform outputs. Have you run 'terraform apply'?"
    exit 1
fi

TF_OUTPUT=$(terraform -chdir=tf output -json oracle_xstream_connector)
DATABASE_HOSTNAME=$(echo "$TF_OUTPUT" | jq -r '.database_hostname')
DATABASE_PORT=$(echo "$TF_OUTPUT" | jq -r '.database_port')
DATABASE_USER=$(echo "$TF_OUTPUT" | jq -r '.database_username')
DATABASE_PASSWORD=$(echo "$TF_OUTPUT" | jq -r '.database_password')

# Basic Validation
if [[ -z "$DATABASE_HOSTNAME" || "$DATABASE_HOSTNAME" == "null" ]]; then
    echo "❌ Error: Could not find database hostname in Terraform outputs."
    exit 1
fi

echo "✅ Connection details retrieved:"
echo "   - Host: $DATABASE_HOSTNAME"
echo "   - Port: $DATABASE_PORT"
echo "   - User: $DATABASE_USER"

# Prepare Configuration File
echo "🔧 Regenerating $CONFIG_FILE from template..."
if [[ ! -f "$TEMPLATE_FILE" ]]; then
    echo "❌ Error: Template file $TEMPLATE_FILE not found."
    exit 1
fi

cp "$TEMPLATE_FILE" "$CONFIG_FILE"

# Use sed to replace placeholders
# -i.bak for compatibility across Linux/macOS, then clean up
sed -i.bak "s/###DATABASE_HOSTNAME###/$DATABASE_HOSTNAME/g" "$CONFIG_FILE"
sed -i.bak "s/###DATABASE_PORT###/$DATABASE_PORT/g" "$CONFIG_FILE"
sed -i.bak "s/###DATABASE_USER###/$DATABASE_USER/g" "$CONFIG_FILE"
sed -i.bak "s/###DATABASE_PASSWORD###/$DATABASE_PASSWORD/g" "$CONFIG_FILE"
rm "${CONFIG_FILE}.bak"

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
