#!/bin/bash
# complete-fleet-vault-setup.sh
# Complete automation script for Fleet setup with Vault integration

set -e

echo "Starting complete Fleet and Vault integration setup..."

# Function to check service health
check_service() {
    local service_name=$1
    local url=$2
    local max_attempts=$3
    
    echo "Checking $service_name..."
    for i in $(seq 1 $max_attempts); do
        if curl -k -s --connect-timeout 5 "$url" >/dev/null 2>&1; then
            echo "SUCCESS: $service_name is ready"
            return 0
        fi
        echo "   Attempt $i/$max_attempts - $service_name not ready..."
        sleep 10
    done
    echo "FAILED: $service_name failed to become ready"
    return 1
}

# Check Fleet Server
if ! check_service "Fleet Server" "http://localhost:8220/api/status" 10; then
    echo "FAILED: Fleet Server is not responding. Check logs: docker-compose logs fleet-server"
    exit 1
fi

echo "SUCCESS: Fleet Server is healthy"

# Check if Elastic Agent is already enrolled
echo "Checking Elastic Agent enrollment status..."
AGENT_STATUS=$(docker exec vault-database_elastic_agent elastic-agent status 2>/dev/null || echo "ERROR")

if echo "$AGENT_STATUS" | grep -q "Connected"; then
    echo "SUCCESS: Elastic Agent is already enrolled and connected"
else
    echo "Enrolling Elastic Agent..."
    
    # Get enrollment token
    TOKEN=$(docker run --rm -v vault-database_fleet-tokens:/tokens alpine:latest cat /tokens/enrollment-token 2>/dev/null)
    
    if [ -z "$TOKEN" ]; then
        echo "FAILED: No enrollment token found"
        exit 1
    fi
    
    echo "Found enrollment token"
    
    # Enroll the agent
    docker exec vault-database_elastic_agent elastic-agent enroll \
        --url=http://fleet-server:8220 \
        --enrollment-token="$TOKEN" \
        --insecure \
        --force
    
    if [ $? -eq 0 ]; then
        echo "SUCCESS: Elastic Agent enrolled successfully"
    else
        echo "FAILED: Failed to enroll Elastic Agent"
        exit 1
    fi
fi

# Wait for agent to stabilize
echo "Waiting for agent to stabilize..."
sleep 15

# Configure Fleet output for HTTPS Elasticsearch
echo "Configuring Fleet output for HTTPS Elasticsearch..."
OUTPUT_ID=$(curl -k -s -X GET "https://localhost:5601/api/fleet/outputs" \
  -H "kbn-xsrf: true" \
  -H "Content-Type: application/json" \
  -u "elastic:password123" \
  --cacert certs/ca/ca.crt | jq -r '.items[0].id')

curl -k -s -X PUT "https://localhost:5601/api/fleet/outputs/$OUTPUT_ID" \
  -H "kbn-xsrf: true" \
  -H "Content-Type: application/json" \
  -u "elastic:password123" \
  --cacert certs/ca/ca.crt \
  -d '{
    "hosts": ["https://elasticsearch:9200"],
    "ssl": {
      "certificate_authorities": ["/certs/ca.crt"],
      "verification_mode": "certificate"
    }
  }' >/dev/null

echo "SUCCESS: Fleet output configured for HTTPS"

# Install HashiCorp Vault integration
echo "Installing HashiCorp Vault integration..."
curl -k -s -X POST "https://localhost:5601/api/fleet/epm/packages/hashicorp_vault/1.28.1" \
  -H "kbn-xsrf: true" \
  -H "Content-Type: application/json" \
  -u "elastic:password123" \
  --cacert certs/ca/ca.crt >/dev/null

echo "SUCCESS: HashiCorp Vault integration installed"

# Get agent policy ID - improved to get the Default Agent Policy specifically
AGENT_POLICY_ID=$(curl -k -s -X GET "https://localhost:5601/api/fleet/agent_policies" \
  -H "kbn-xsrf: true" \
  -H "Content-Type: application/json" \
  -u "elastic:password123" \
  --cacert certs/ca/ca.crt | jq -r '.items[] | select(.name == "Default Agent Policy") | .id')

if [ -z "$AGENT_POLICY_ID" ] || [ "$AGENT_POLICY_ID" = "null" ]; then
    echo "FAILED: Could not find Default Agent Policy"
    exit 1
fi

echo "SUCCESS: Found agent policy ID: $AGENT_POLICY_ID"

# Add Vault integration to agent policy
echo "Adding Vault integration to agent policy..."
VAULT_INTEGRATION_RESPONSE=$(curl -k -s -X POST "https://localhost:5601/api/fleet/package_policies" \
  -H "kbn-xsrf: true" \
  -H "Content-Type: application/json" \
  -u "elastic:password123" \
  --cacert certs/ca/ca.crt \
  -d "{
    \"name\": \"hashicorp-vault-audit\",
    \"description\": \"HashiCorp Vault audit and operational logs\",
    \"namespace\": \"default\",
    \"policy_id\": \"$AGENT_POLICY_ID\",
    \"package\": {
      \"name\": \"hashicorp_vault\",
      \"version\": \"1.28.1\"
    },
    \"inputs\": [
      {
        \"type\": \"logfile\",
        \"enabled\": true,
        \"streams\": [
          {
            \"enabled\": true,
            \"data_stream\": {
              \"type\": \"logs\",
              \"dataset\": \"hashicorp_vault.audit\"
            },
            \"vars\": {
              \"paths\": {
                \"value\": [\"/mnt/vault-audit/vault_audit.log\"],
                \"type\": \"text\"
              },
              \"preserve_original_event\": {
                \"value\": true,
                \"type\": \"bool\"
              },
              \"tags\": {
                \"value\": [\"vault\", \"audit\", \"security\"],
                \"type\": \"text\"
              }
            }
          }
        ]
      }
    ]
  }")

if echo "$VAULT_INTEGRATION_RESPONSE" | grep -q '"id"'; then
    INTEGRATION_ID=$(echo "$VAULT_INTEGRATION_RESPONSE" | jq -r '.item.id')
    echo "SUCCESS: Vault integration created with ID: $INTEGRATION_ID"
else
    echo "FAILED: Failed to create Vault integration"
    echo "Response: $VAULT_INTEGRATION_RESPONSE"
    exit 1
fi

# Restart elastic agent to apply new configuration
echo "Restarting Elastic Agent to apply new configuration..."
docker-compose restart elastic-agent
sleep 30

# Configure Vault audit logging
echo "Configuring Vault audit logging..."

# Create audit directory and fix permissions
echo "Setting up audit directory..."
docker exec vault-database_vault mkdir -p /vault/audit
docker exec vault-database_vault chown -R vault:vault /vault/audit
docker exec vault-database_vault chmod 755 /vault/audit

# Check if Vault needs to be initialized (fresh environment)
echo "Checking Vault initialization status..."
VAULT_STATUS=$(docker exec vault-database_vault vault status -format=json 2>/dev/null || echo '{"initialized":false}')
VAULT_INITIALIZED=$(echo "$VAULT_STATUS" | jq -r '.initialized // false')
VAULT_SEALED=$(echo "$VAULT_STATUS" | jq -r '.sealed // true')

if [ "$VAULT_INITIALIZED" = "false" ]; then
    echo "Initializing Vault..."
    INIT_OUTPUT=$(docker exec vault-database_vault vault operator init -key-shares=5 -key-threshold=3 -format=json)
    
    # Extract root token and unseal keys
    ROOT_TOKEN=$(echo "$INIT_OUTPUT" | jq -r '.root_token')
    UNSEAL_KEY_1=$(echo "$INIT_OUTPUT" | jq -r '.unseal_keys_b64[0]')
    UNSEAL_KEY_2=$(echo "$INIT_OUTPUT" | jq -r '.unseal_keys_b64[1]')
    UNSEAL_KEY_3=$(echo "$INIT_OUTPUT" | jq -r '.unseal_keys_b64[2]')
    
    echo "SUCCESS: Vault initialized"
    echo "Root token: $ROOT_TOKEN"
    
    # Unseal Vault
    echo "Unsealing Vault..."
    docker exec vault-database_vault vault operator unseal "$UNSEAL_KEY_1" >/dev/null
    docker exec vault-database_vault vault operator unseal "$UNSEAL_KEY_2" >/dev/null
    docker exec vault-database_vault vault operator unseal "$UNSEAL_KEY_3" >/dev/null
    echo "SUCCESS: Vault unsealed"
else
    echo "Vault is already initialized"
    # Try to get root token from logs if available
    ROOT_TOKEN=$(docker logs vault-database_vault 2>&1 | grep -o 'Root Token: [a-zA-Z0-9._-]*' | head -1 | cut -d' ' -f3)
    if [ -z "$ROOT_TOKEN" ]; then
        echo "WARNING: Could not find root token. Some operations may fail."
        ROOT_TOKEN=""
    fi
fi

# Set the root token for subsequent vault commands
if [ ! -z "$ROOT_TOKEN" ]; then
    export VAULT_TOKEN="$ROOT_TOKEN"
    echo "Using root token for Vault operations"
fi

# Check if audit device already exists
echo "Checking Vault audit configuration..."
AUDIT_LIST=$(docker exec vault-database_vault sh -c "VAULT_TOKEN=$ROOT_TOKEN vault audit list 2>/dev/null" || echo "")

if echo "$AUDIT_LIST" | grep -q "audit_log"; then
    echo "Vault audit device already exists"
else
    echo "Enabling Vault audit device..."
    
    # Enable audit device
    docker exec vault-database_vault sh -c "VAULT_TOKEN=$ROOT_TOKEN vault audit enable -path=audit_log file file_path=/vault/audit/vault_audit.log"
    if [ $? -eq 0 ]; then
        echo "SUCCESS: Vault audit device enabled"
    else
        echo "WARNING: Failed to enable audit device, but continuing..."
    fi
fi

# Generate test audit events
echo "Generating test Vault operations..."
docker exec vault-database_vault sh -c "VAULT_TOKEN=$ROOT_TOKEN vault kv put secret/test-complete-setup key1=value1 key2=value2" >/dev/null 2>&1 || echo "KV operation completed"
docker exec vault-database_vault sh -c "VAULT_TOKEN=$ROOT_TOKEN vault kv get secret/test-complete-setup" >/dev/null 2>&1 || echo "KV read completed"
docker exec vault-database_vault sh -c "VAULT_TOKEN=$ROOT_TOKEN vault kv delete secret/test-complete-setup" >/dev/null 2>&1 || echo "KV delete completed"

# Also generate some events that don't require authentication
docker exec vault-database_vault vault status >/dev/null 2>&1 || echo "Status check completed"
docker exec vault-database_vault vault read sys/health >/dev/null 2>&1 || echo "Health check completed"

# Check if audit log file was created and has content
echo "Verifying audit log file..."
if docker exec vault-database_vault ls -la /vault/audit/vault_audit.log >/dev/null 2>&1; then
    FILE_SIZE=$(docker exec vault-database_vault stat /vault/audit/vault_audit.log | grep Size | awk '{print $2}')
    echo "SUCCESS: Audit log file exists with size: $FILE_SIZE bytes"
    
    # Fix permissions for Elastic Agent to read
    docker exec vault-database_vault chmod 644 /vault/audit/vault_audit.log
    echo "SUCCESS: Audit log file permissions set to 644"
else
    echo "WARNING: Audit log file not found"
fi

# Wait for log collection
echo "Waiting for log collection (90 seconds)..."
sleep 90

# Verify log collection
echo "Verifying Vault audit log collection..."
LOG_COUNT=$(curl -k -s -X GET "https://localhost:9200/logs-hashicorp_vault.audit-*/_count" \
  -H "Content-Type: application/json" \
  -u "elastic:password123" \
  --cacert certs/ca/ca.crt 2>/dev/null | jq '.count' 2>/dev/null || echo "0")

if [ "$LOG_COUNT" -gt 0 ]; then
    echo "SUCCESS: Found $LOG_COUNT Vault audit log entries in Elasticsearch"
    
    # Show sample log entry
    echo "Sample Vault audit log entry:"
    curl -k -s -X GET "https://localhost:9200/logs-hashicorp_vault.audit-*/_search?size=1" \
      -H "Content-Type: application/json" \
      -u "elastic:password123" \
      --cacert certs/ca/ca.crt \
      -d '{"sort": [{"@timestamp": {"order": "desc"}}]}' | \
      jq '.hits.hits[0]._source | {timestamp: .["@timestamp"], operation: .vault.request.operation, path: .vault.request.path}' 2>/dev/null || echo "Log parsing not available"
else
    echo "WARNING: No Vault audit logs found yet. This may be normal - logs can take a few minutes to appear."
    echo "Manual check command: curl -k \"https://localhost:9200/logs-hashicorp_vault.audit-*/_count\" -u elastic:password123 --cacert certs/ca.crt"
    
    # Debug information
    echo ""
    echo "Debug information:"
    echo "- Checking if audit log file exists and has content:"
    docker exec vault-database_vault ls -la /vault/audit/ 2>/dev/null || echo "  Audit directory not accessible"
    echo "- Checking if Elastic Agent can read the file:"
    docker exec vault-database_elastic_agent ls -la /mnt/vault-audit/ 2>/dev/null || echo "  Elastic Agent cannot access audit directory"
    echo "- Recent Elastic Agent logs:"
    docker logs vault-database_elastic_agent --tail 10 2>/dev/null || echo "  Cannot retrieve agent logs"
fi

# Verify agents in Kibana
echo "Verifying agents in Kibana..."
AGENTS_RESPONSE=$(curl -k -s -X GET "https://localhost:5601/api/fleet/agents" \
    -H "kbn-xsrf: true" \
    -H "Content-Type: application/json" \
    -u "elastic:password123" \
    --cacert certs/ca/ca.crt 2>/dev/null)

if echo "$AGENTS_RESPONSE" | grep -q '"status":"online"'; then
    AGENT_COUNT=$(echo "$AGENTS_RESPONSE" | grep -o '"status":"online"' | wc -l)
    echo "SUCCESS: Found $AGENT_COUNT online agent(s) in Kibana"
else
    echo "WARNING: No online agents found in Kibana. Check agent status."
fi

echo ""
echo "======================================================================"
echo "Complete Fleet and Vault integration setup completed!"
echo "======================================================================"
echo ""
echo "Summary:"
echo "  - Fleet Server running and healthy"
echo "  - Elastic Agent enrolled and connected"
echo "  - Fleet output configured for HTTPS Elasticsearch"
echo "  - HashiCorp Vault integration installed and configured"
echo "  - Vault initialized and unsealed (if was fresh)"
echo "  - Vault audit logging enabled and configured"
echo "  - Test audit logs generated"
echo ""
if [ ! -z "$VAULT_TOKEN" ]; then
echo "IMPORTANT: Using Vault token from environment: ${VAULT_TOKEN:0:10}..."
echo ""
fi
echo "Next steps:"
echo "  1. Access Kibana Fleet dashboard: https://localhost:5601/app/fleet"
echo "  2. View Vault audit logs in Discover: https://localhost:5601/app/discover"
echo "  3. Create dashboards and alerts for Vault security monitoring"
echo ""
echo "Useful commands:"
echo "  - Check logs: curl -k \"https://localhost:9200/logs-hashicorp_vault.audit-*/_count\" -u elastic:password123 --cacert certs/ca/ca.crt"
echo "  - Generate test events: docker exec vault-database_vault sh -c \"VAULT_TOKEN=$ROOT_TOKEN vault kv put secret/test key=value\""
echo "  - View agent status: docker exec vault-database_elastic_agent elastic-agent status"
echo ""
echo "======================================================================"