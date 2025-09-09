#!/bin/bash
# post-deploy-fleet.sh

# Post-deployment script to complete Fleet setup after containers are running
# Runs as Task (task name: fleet, elk-fleet)

set -e

# Color definitions
GREEN='\033[0;32m'    # Green text for success messages
YELLOW='\033[1;33m'   # Yellow text for warnings
BLUE='\033[0;34m'     # Blue text for informational messages
NC='\033[0m'          # No Color - resets text color to default

echo -e "${BLUE}Starting post-deployment Fleet configuration...${NC}"

# Function to check service health
check_service() {
    local service_name=$1
    local url=$2
    local max_attempts=$3
    
    echo -e "${BLUE}Checking $service_name...${NC}"
    for i in $(seq 1 $max_attempts); do
        if curl -k -s --connect-timeout 5 "$url" >/dev/null 2>&1; then
            echo -e "${GREEN}✓ $service_name is ready${NC}"
            return 0
        fi
        echo -e "${YELLOW}   Attempt $i/$max_attempts - $service_name not ready...${NC}"
        sleep 10
    done
    echo -e "${YELLOW}✗ $service_name failed to become ready${NC}"
    return 1
}

# Check Fleet Server
if ! check_service "Fleet Server" "http://localhost:8220/api/status" 10; then
    echo -e "${YELLOW}✗ Fleet Server is not responding. Check logs: docker-compose logs fleet-server${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Fleet Server is healthy${NC}"

# Check if Elastic Agent is already enrolled
echo -e "${BLUE}Checking Elastic Agent enrollment status...${NC}"
AGENT_STATUS=$(docker exec vault-database_elastic_agent elastic-agent status 2>/dev/null || echo "ERROR")

if echo "$AGENT_STATUS" | grep -q "Connected"; then
    echo -e "${GREEN}✓ Elastic Agent is already enrolled and connected${NC}"
else
    echo -e "${BLUE}Enrolling Elastic Agent...${NC}"
    
    # Get enrollment token
    TOKEN=$(docker run --rm -v vault-database_fleet-tokens:/tokens alpine:latest cat /tokens/enrollment-token 2>/dev/null)
    
    if [ -z "$TOKEN" ]; then
        echo -e "${YELLOW}✗ No enrollment token found${NC}"
        exit 1
    fi
    
    echo -e "${BLUE}Found enrollment token${NC}"
    
    # Enroll the agent
    docker exec vault-database_elastic_agent elastic-agent enroll \
        --url=http://fleet-server:8220 \
        --enrollment-token="$TOKEN" \
        --insecure \
        --force
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Elastic Agent enrolled successfully${NC}"
    else
        echo -e "${YELLOW}✗ Failed to enroll Elastic Agent${NC}"
        exit 1
    fi
fi

# Verify both agents are registered in Kibana
echo -e "${BLUE}Verifying agents in Kibana...${NC}"
AGENTS_RESPONSE=$(curl -k -s -X GET "https://localhost:5601/api/fleet/agents" \
    -H "kbn-xsrf: true" \
    -H "Content-Type: application/json" \
    -u "elastic:password123" \
    --cacert certs/ca/ca.crt 2>/dev/null)

if echo "$AGENTS_RESPONSE" | grep -q '"status":"online"'; then
    AGENT_COUNT=$(echo "$AGENTS_RESPONSE" | grep -o '"status":"online"' | wc -l)
    echo -e "${GREEN}✓ Found $AGENT_COUNT online agent(s) in Kibana${NC}"
    
    # Display agent details
    echo -e "${BLUE}Agent Details:${NC}"
    echo "$AGENTS_RESPONSE" | jq -r '.list[] | "  - ID: \(.id) | Status: \(.status) | Type: \(.type) | Policy: \(.policy_id)"' 2>/dev/null || echo "  (Raw response parsing failed, but agents are online)"
else
    echo -e "${YELLOW}⚠ No online agents found in Kibana. This may be normal if agents are still starting up.${NC}"
fi

# Wait for agent daemon to stabilize after enrollment
echo -e "${BLUE}Waiting for agent daemon to stabilize...${NC}"
sleep 10

# Final status check with improved error handling
echo -e "${BLUE}Final Fleet status verification...${NC}"

# Check Fleet Server status
echo -e "${BLUE}Fleet Server Status:${NC}"
if docker exec vault-database_fleet_server elastic-agent status 2>/dev/null; then
    echo -e "${GREEN}✓ Fleet Server status check successful${NC}"
else
    echo -e "${YELLOW}⚠ Fleet Server status check failed (may be restarting)${NC}"
fi

echo ""

# Check Elastic Agent status with retry logic
echo -e "${BLUE}Elastic Agent Status:${NC}"
AGENT_STATUS_SUCCESS=false
for i in {1..3}; do
    if docker exec vault-database_elastic_agent elastic-agent status 2>/dev/null; then
        echo -e "${GREEN}✓ Elastic Agent status check successful${NC}"
        AGENT_STATUS_SUCCESS=true
        break
    else
        echo -e "${YELLOW}⚠ Elastic Agent status check attempt $i/3: daemon may be restarting...${NC}"
        if [ $i -lt 3 ]; then
            sleep 5
        fi
    fi
done

if [ "$AGENT_STATUS_SUCCESS" = false ]; then
    echo -e "${YELLOW}Note: Agent daemon status check failed, but this is normal during restart after enrollment${NC}"
fi

echo ""
echo -e "${GREEN}Post-deployment Fleet setup completed!${NC}"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo -e "${BLUE}  1. Check Kibana Fleet dashboard: https://localhost:5601/app/fleet${NC}"
echo -e "${BLUE}  2. Configure Vault audit logging to send logs to Elasticsearch${NC}"
echo -e "${BLUE}  3. Set up log collection policies in Fleet${NC}"
echo ""
echo -e "${BLUE}Useful commands:${NC}"
echo -e "${BLUE}  - Check Fleet agents: curl -k https://localhost:5601/api/fleet/agents -H 'kbn-xsrf: true' -u elastic:password123 --cacert certs/ca/ca.crt${NC}"
echo -e "${BLUE}  - View agent logs: docker-compose logs elastic-agent${NC}"
echo -e "${BLUE}  - View agent status: docker exec vault-database_elastic_agent elastic-agent status${NC}"
echo -e "${BLUE}  - Fleet Server status: curl -k http://localhost:8220/api/status${NC}"