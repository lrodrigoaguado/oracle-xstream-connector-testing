#!/bin/bash

# Find the Oracle Instant Client RPM in the etc folder
ORACLE_RPM=$(ls etc/oracle-instantclient-basic-*.rpm 2>/dev/null | head -n 1)

if [ -z "$ORACLE_RPM" ]; then
    echo "❌ Error: Oracle Instant Client RPM not found in 'etc/' folder."
    echo "Please download it from Oracle and place it in the 'etc/' directory."
    echo "Example: etc/oracle-instantclient-basic-23.26.0.0.0-1.el8.aarch64.rpm"
    exit 1
fi

ORACLE_RPM_FILENAME=$(basename "$ORACLE_RPM")
echo "✅ Found Oracle RPM: $ORACLE_RPM_FILENAME"

# Update Dockerfile with the found RPM filename
echo "🔧 Updating Dockerfile..."
# Use sed to replace the oracle-instantclient-basic-*.rpm pattern
sed -i.bak "s/###oracle-instantclient-anchor###/$ORACLE_RPM_FILENAME/g" Dockerfile

if [ $? -eq 0 ]; then
    echo "✨ Dockerfile updated successfully."
    rm Dockerfile.bak
else
    echo "❌ Failed to update Dockerfile."
    exit 1
fi

# Run docker-compose
echo "🚀 Starting environment..."
docker-compose up -d --build --force-recreate
