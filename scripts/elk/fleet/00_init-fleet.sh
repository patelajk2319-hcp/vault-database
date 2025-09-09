#!/bin/sh
# scripts/elk/fleet/init-fleet.sh
# This script initializes Elastic Fleet in a Kibana environment.
# It sets up Fleet, configures outputs, creates policies, and generates tokens for Fleet Server and agent enrollment.

# Exit immediately if a command exits with a non-zero status
set -e

echo "Initializing Fleet setup..."

# -----------------------
# Wait for Kibana to be ready
# -----------------------
echo "Waiting for Kibana to be ready..."
for i in $(seq 1 30); do
    # Attempt to check Kibana status using its API
    if curl -k -s --fail --cacert "$CA_CERT" -u "$KIBANA_USER:$KIBANA_PASSWORD" \
       "$KIBANA_HOST/api/status" > /dev/null 2>&1; then
        echo "Kibana is ready!"
        break
    fi
    echo "   Attempt $i/30 - Kibana not ready yet, waiting..."
    sleep 10
done

# -----------------------
# Initialize Fleet
# -----------------------
echo "Setting up Fleet..."
curl -k -s -X POST "$KIBANA_HOST/api/fleet/setup" \
  -H "kbn-xsrf: true" \
  -H "Content-Type: application/json" \
  -u "$KIBANA_USER:$KIBANA_PASSWORD" \
  --cacert "$CA_CERT" || echo "Fleet may already be initialized"

sleep 5

# -----------------------
# Configure the default Elasticsearch output
# -----------------------
echo "Configuring default Elasticsearch output..."
curl -k -s -X POST "$KIBANA_HOST/api/fleet/outputs" \
  -H "kbn-xsrf: true" \
  -H "Content-Type: application/json" \
  -u "$KIBANA_USER:$KIBANA_PASSWORD" \
  --cacert "$CA_CERT" \
  -d '{
    "id": "fleet-default-output",
    "name": "default",
    "type": "elasticsearch",
    "is_default": true,
    "hosts": ["https://elasticsearch:9200"],
    "config_yaml": "ssl.certificate_authorities: [\"/certs/ca.crt\"]\nssl.verification_mode: certificate"
  }' || echo "Default output may already exist - attempting update..."

# If creation failed, update existing default output
echo "Ensuring default output has correct configuration..."
curl -k -s -X PUT "$KIBANA_HOST/api/fleet/outputs/fleet-default-output" \
  -H "kbn-xsrf: true" \
  -H "Content-Type: application/json" \
  -u "$KIBANA_USER:$KIBANA_PASSWORD" \
  --cacert "$CA_CERT" \
  -d '{
    "name": "default",
    "type": "elasticsearch",
    "hosts": ["https://elasticsearch:9200"],
    "config_yaml": "ssl.certificate_authorities: [\"/certs/ca.crt\"]\nssl.verification_mode: certificate"
  }' || echo "Output configuration update completed"

sleep 3

# -----------------------
# Create Fleet Server service token
# -----------------------
echo "Creating Fleet Server service token..."
FLEET_TOKEN_RESPONSE=$(curl -k -s -X POST "$KIBANA_HOST/api/fleet/service-tokens" \
  -H "kbn-xsrf: true" \
  -H "Content-Type: application/json" \
  -H "elastic-api-version: 1" \
  -u "$KIBANA_USER:$KIBANA_PASSWORD" \
  --cacert "$CA_CERT")

# Extract token from response
if echo "$FLEET_TOKEN_RESPONSE" | grep -q "value"; then
    FLEET_SERVER_TOKEN=$(echo "$FLEET_TOKEN_RESPONSE" | grep -o '"value":"[^"]*"' | cut -d'"' -f4)
    echo "$FLEET_SERVER_TOKEN" > /tokens/fleet-server-token
    echo "Fleet Server token created and saved"
else
    echo "Failed to create Fleet Server token"
    exit 1
fi

# -----------------------
# Install Fleet Server package
# -----------------------
echo "Installing Fleet Server package..."
curl -k -s -X POST "$KIBANA_HOST/api/fleet/epm/packages/fleet_server/1.6.0" \
  -H "kbn-xsrf: true" \
  -H "Content-Type: application/json" \
  -u "$KIBANA_USER:$KIBANA_PASSWORD" \
  --cacert "$CA_CERT" || echo "Package may already be installed"

sleep 3

# -----------------------
# Create Fleet Server policy
# -----------------------
echo "Creating Fleet Server policy..."
FLEET_SERVER_POLICY_RESPONSE=$(curl -k -s -X POST "$KIBANA_HOST/api/fleet/agent_policies" \
  -H "kbn-xsrf: true" \
  -H "Content-Type: application/json" \
  -u "$KIBANA_USER:$KIBANA_PASSWORD" \
  --cacert "$CA_CERT" \
  -d '{
    "id": "fleet-server-policy",
    "name": "Fleet Server Policy",
    "description": "Policy for Fleet Server",
    "namespace": "default",
    "monitoring_enabled": ["logs", "metrics"],
    "is_default_fleet_server": true
  }')

echo "Fleet Server policy response: $FLEET_SERVER_POLICY_RESPONSE"

sleep 3

# -----------------------
# Add Fleet Server integration to the policy
# -----------------------
echo "Adding Fleet Server integration to policy..."
curl -k -s -X POST "$KIBANA_HOST/api/fleet/package_policies" \
  -H "kbn-xsrf: true" \
  -H "Content-Type: application/json" \
  -u "$KIBANA_USER:$KIBANA_PASSWORD" \
  --cacert "$CA_CERT" \
  -d '{
    "name": "fleet_server-1",
    "description": "Fleet Server integration",
    "namespace": "default",
    "policy_id": "fleet-server-policy",
    "package": {
      "name": "fleet_server",
      "version": "1.6.0"
    },
    "inputs": [
      {
        "type": "fleet-server",
        "enabled": true,
        "streams": [],
        "vars": {
          "host": {
            "value": "0.0.0.0",
            "type": "text"
          },
          "port": {
            "value": 8220,
            "type": "integer"
          }
        }
      }
    ]
  }' || echo "Integration may already exist"

sleep 3

# -----------------------
# Create Default Agent policy for regular agents
# -----------------------
echo "Creating Default Agent policy..."
AGENT_POLICY_RESPONSE=$(curl -k -s -X POST "$KIBANA_HOST/api/fleet/agent_policies" \
  -H "kbn-xsrf: true" \
  -H "Content-Type: application/json" \
  -u "$KIBANA_USER:$KIBANA_PASSWORD" \
  --cacert "$CA_CERT" \
  -d '{
    "name": "Default Agent Policy",
    "description": "Default policy for Elastic Agents",
    "namespace": "default",
    "monitoring_enabled": ["logs", "metrics"]
  }')

POLICY_ID=$(echo "$AGENT_POLICY_RESPONSE" | grep -o '"id":"[^"]*"' | cut -d'"' -f4)
echo "Created agent policy with ID: $POLICY_ID"

sleep 3

# -----------------------
# Create enrollment token for agent enrollment
# -----------------------
echo "Creating enrollment token..."
ENROLLMENT_RESPONSE=$(curl -k -s -X POST "$KIBANA_HOST/api/fleet/enrollment-api-keys" \
  -H "kbn-xsrf: true" \
  -H "Content-Type: application/json" \
  -H "elastic-api-version: 1" \
  -u "$KIBANA_USER:$KIBANA_PASSWORD" \
  --cacert "$CA_CERT" \
  -d "{\"policy_id\": \"$POLICY_ID\"}")

if echo "$ENROLLMENT_RESPONSE" | grep -q '"api_key"'; then
    ENROLLMENT_TOKEN=$(echo "$ENROLLMENT_RESPONSE" | grep -o '"api_key":"[^"]*"' | cut -d'"' -f4)
    echo "$ENROLLMENT_TOKEN" > /tokens/enrollment-token
    echo "Enrollment token created and saved"
else
    echo "Failed to create enrollment token"
    echo "Response: $ENROLLMENT_RESPONSE"
    exit 1
fi

echo "Fleet initialization completed successfully!"
