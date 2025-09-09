#!/bin/bash
# extract-service-token.sh - Extract service token from Fleet Server logs and use it

set -e

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🔍 Extracting Service Token from Fleet Server Logs${NC}"
echo "=================================================="

# Check if Fleet Server is running
if ! docker-compose ps fleet-server | grep -q "Up"; then
    echo -e "${RED}❌ Fleet Server is not running${NC}"
    exit 1
fi

# Extract the latest service token from logs
echo -e "\n${BLUE}📋 Looking for service tokens in Fleet Server logs...${NC}"
TOKEN_NAME=$(docker-compose logs fleet-server | grep "Created service_token named:" | tail -1 | sed 's/.*Created service_token named: //')

if [ -z "$TOKEN_NAME" ]; then
    echo -e "${RED}❌ No service token found in logs${NC}"
    echo -e "${YELLOW}💡 Make sure Fleet Server has attempted to start at least once${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Found service token: $TOKEN_NAME${NC}"

# Now get the actual token value from Kibana using the token name
echo -e "\n${BLUE}🔑 Retrieving token value from Kibana...${NC}"

# List all service tokens to find our token
TOKEN_VALUE=$(curl -k -s -X GET "https://localhost:5601/api/fleet/service-tokens" \
    -H "kbn-xsrf: true" \
    -u "elastic:password123" \
    --cacert certs/ca/ca.crt | \
    jq -r --arg name "$TOKEN_NAME" '.items[] | select(.name == $name) | .value' 2>/dev/null)

if [ -n "$TOKEN_VALUE" ] && [ "$TOKEN_VALUE" != "null" ]; then
    echo -e "${GREEN}✅ Service token value retrieved${NC}"
    echo "Token: $TOKEN_VALUE"
    
    # Update .env file
    if [ -f .env ]; then
        sed -i '/^FLEET_SERVER_SERVICE_TOKEN=/d' .env
        echo "FLEET_SERVER_SERVICE_TOKEN=$TOKEN_VALUE" >> .env
        echo -e "${GREEN}✅ .env file updated${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  Could not retrieve token value, trying direct API creation...${NC}"
    
    # Create a new service token directly
    TOKEN_VALUE=$(curl -k -s -X POST "https://localhost:5601/api/fleet/service-tokens" \
        -H "kbn-xsrf: true" \
        -H "Content-Type: application/json" \
        -u "elastic:password123" \
        --cacert certs/ca/ca.crt | jq -r '.value' 2>/dev/null)
    
    if [ -n "$TOKEN_VALUE" ] && [ "$TOKEN_VALUE" != "null" ]; then
        echo -e "${GREEN}✅ New service token created${NC}"
        echo "Token: $TOKEN_VALUE"
        
        # Update .env file
        if [ -f .env ]; then
            sed -i '/^FLEET_SERVER_SERVICE_TOKEN=/d' .env
            echo "FLEET_SERVER_SERVICE_TOKEN=$TOKEN_VALUE" >> .env
            echo -e "${GREEN}✅ .env file updated${NC}"
        fi
    else
        echo -e "${RED}❌ Failed to create service token${NC}"
        exit 1
    fi
fi

# Stop Fleet Server auto-enrollment loop
echo -e "\n${BLUE}🛑 Stopping Fleet Server...${NC}"
docker-compose stop fleet-server
docker-compose rm -f fleet-server

# Clear the problematic volume
echo -e "${BLUE}🗑 Clearing Fleet Server data...${NC}"
docker volume rm $(docker volume ls -q | grep fleet-server) 2>/dev/null || true

echo -e "\n${GREEN}🎉 Service token extracted and configured!${NC}"
echo "============================================"
echo -e "${BLUE}📝 Next steps:${NC}"
echo "1. Start Fleet Server with the extracted token:"
echo "   docker-compose up -d fleet-server"
echo ""
echo "2. Monitor Fleet Server logs (should start successfully now):"
echo "   docker-compose logs -f fleet-server"
echo ""
echo "3. Once Fleet Server is running, generate enrollment token:"
echo "   ./generate-enrollment-token.sh"
echo ""
echo "4. Start Elastic Agent:"
echo "   docker-compose up -d elastic-agent"