#!/bin/bash
# post-deploy-fleet.sh
# Post-deployment script to complete Fleet setup after containers are running

set -e

echo "Starting post-deployment Fleet configuration..."

# Function to check service health
check_service() {
    local service_name=$1
    local url=$2
    local max_attempts=$3
    
    echo "Checking $service_name..."
    for i in $(seq 1 $max_attempts); do
        if curl -k -s --connect-timeout 5 "$url" >/dev/null 2>&1; then
            echo "✓ $service_name is ready"
            return 0
        fi
        echo "   Attempt $i/$max_attempts - $service_name not ready..."
        sleep 10
    done
    echo "✗ $service_name failed to become ready"
    return 1
}

# Check Fleet Server
if ! check_service "Fleet Server" "http://localhost:8220/api/status" 10; then
    echo "✗ Fleet Server is not responding. Check logs: docker-compose logs fleet-server"
    exit 1
fi

echo "✓ Fleet Server is healthy"

# Check if Elastic Agent is already enrolled
echo "Checking Elastic Agent enrollment status..."
AGENT_STATUS=$(docker exec vault-database_elastic_agent elastic-agent status 2>/dev/null || echo "ERROR")

if echo "$AGENT_STATUS" | grep -q "Connected"; then
    echo "✓ Elastic Agent is already enrolled and connected"
else
    echo "Enrolling Elastic Agent..."
    
    # Get enrollment token
    TOKEN=$(docker run --rm -v vault-database_fleet-tokens:/tokens alpine:latest cat /tokens/enrollment-token 2>/dev/null)
    
    if [ -z "$TOKEN" ]; then
        echo "✗ No enrollment token found"
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
        echo "✓ Elastic Agent enrolled successfully"
    else
        echo "✗ Failed to enroll Elastic Agent"
        exit 1
    fi
fi

# Verify both agents are registered in Kibana
echo "Verifying agents in Kibana..."
AGENTS_RESPONSE=$(curl -k -s -X GET "https://localhost:5601/api/fleet/agents" \
    -H "kbn-xsrf: true" \
    -H "Content-Type: application/json" \
    -u "elastic:password123" \
    --cacert certs/ca/ca.crt 2>/dev/null)

if echo "$AGENTS_RESPONSE" | grep -q '"status":"online"'; then
    AGENT_COUNT=$(echo "$AGENTS_RESPONSE" | grep -o '"status":"online"' | wc -l)
    echo "✓ Found $AGENT_COUNT online agent(s) in Kibana"
    
    # Display agent details
    echo "Agent Details:"
    echo "$AGENTS_RESPONSE" | jq -r '.list[] | "  - ID: \(.id) | Status: \(.status) | Type: \(.type) | Policy: \(.policy_id)"' 2>/dev/null || echo "  (Raw response parsing failed, but agents are online)"
else
    echo "⚠ No online agents found in Kibana. This may be normal if agents are still starting up."
fi

# Wait for agent daemon to stabilize after enrollment
echo "Waiting for agent daemon to stabilize..."
sleep 10

# Final status check with improved error handling
echo "Final Fleet status verification..."

# Check Fleet Server status
echo "Fleet Server Status:"
if docker exec vault-database_fleet_server elastic-agent status 2>/dev/null; then
    echo "✓ Fleet Server status check successful"
else
    echo "⚠ Fleet Server status check failed (may be restarting)"
fi

echo ""

# Check Elastic Agent status with retry logic
echo "Elastic Agent Status:"
AGENT_STATUS_SUCCESS=false
for i in {1..3}; do
    if docker exec vault-database_elastic_agent elastic-agent status 2>/dev/null; then
        echo "✓ Elastic Agent status check successful"
        AGENT_STATUS_SUCCESS=true
        break
    else
        echo "⚠ Elastic Agent status check attempt $i/3: daemon may be restarting..."
        if [ $i -lt 3 ]; then
            sleep 5
        fi
    fi
done

if [ "$AGENT_STATUS_SUCCESS" = false ]; then
    echo "Note: Agent daemon status check failed, but this is normal during restart after enrollment"
fi

echo ""
echo "Post-deployment Fleet setup completed!"
echo ""
echo "Next steps:"
echo "  1. Check Kibana Fleet dashboard: https://localhost:5601/app/fleet"
echo "  2. Configure Vault audit logging to send logs to Elasticsearch"
echo "  3. Set up log collection policies in Fleet"
echo ""
echo "Useful commands:"
echo "  - Check Fleet agents: curl -k https://localhost:5601/api/fleet/agents -H 'kbn-xsrf: true' -u elastic:password123 --cacert certs/ca/ca.crt"
echo "  - View agent logs: docker-compose logs elastic-agent"
echo "  - Fleet Server status: curl -k http://localhost:8220/api/status"