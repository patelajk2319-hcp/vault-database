#!/bin/sh
# scripts/elk/fleet/start-fleet-server.sh

set -e

echo "Starting Fleet Server..."

# Wait for token file to be available
echo "Waiting for Fleet Server token..."
for i in $(seq 1 30); do
    if [ -f "/tokens/fleet-server-token" ]; then
        TOKEN=$(cat /tokens/fleet-server-token)
        if [ -n "$TOKEN" ]; then
            echo "Fleet Server token found!"
            break
        fi
    fi
    echo "   Attempt $i/30 - Waiting for token..."
    sleep 5
done

if [ -z "$TOKEN" ]; then
    echo "Failed to get Fleet Server token"
    exit 1
fi

# Export the token as environment variable
export FLEET_SERVER_SERVICE_TOKEN="$TOKEN"

echo "Starting Fleet Server enrollment process..."

# Enroll Fleet Server first
elastic-agent enroll \
  --fleet-server-es=https://elasticsearch:9200 \
  --fleet-server-service-token="$TOKEN" \
  --fleet-server-policy=fleet-server-policy \
  --fleet-server-es-ca=/certs/ca.crt \
  --fleet-server-insecure-http \
  --fleet-server-host=0.0.0.0 \
  --fleet-server-port=8220 \
  --force

echo "Starting Fleet Server..."

# Start the Fleet Server
exec elastic-agent run