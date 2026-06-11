#!/bin/bash
set -e

# Detect RPMs in etc folder
LIBAIO_RPM=$(ls etc/libaio-*.rpm 2>/dev/null | head -n 1 | xargs basename 2>/dev/null)
INSTANT_CLIENT_RPM=$(ls etc/oracle-instantclient-basic-*.rpm 2>/dev/null | head -n 1 | xargs basename 2>/dev/null)

if [ -z "$LIBAIO_RPM" ] || [ -z "$INSTANT_CLIENT_RPM" ]; then
    echo "❌ Error: Oracle Instant Client RPMs not found in etc/ folder."
    echo "Please download the libaio and instant-client-basic RPMs from Oracle and place them in the etc/ directory."
    exit 1
fi

echo "📦 Found RPMs: "
echo "  - Libaio: $LIBAIO_RPM"
echo "  - Instant Client: $INSTANT_CLIENT_RPM"
echo ""

# Build custom SMT
echo "🔨 Building custom SMT JAR..."
mvn clean package -f smt/pom.xml -DskipTests
echo ""

# Build with detected RPMs
echo "🚀 Building Kafka Connect image..."
docker compose build --build-arg LIBAIO_RPM="$LIBAIO_RPM" --build-arg INSTANT_CLIENT_RPM="$INSTANT_CLIENT_RPM"

# Start environment
echo "🌟 Starting all services..."
docker compose up -d

echo ""
echo "✅ Environment started. Check 'docker logs -f oracle-19' for XStream status."
echo "Once XStream is ready, run ./bin/02_verify_oracle_status.sh to confirm."
