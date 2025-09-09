#!/bin/bash
# test-fleet-deployment.sh
# Comprehensive test script to validate Fleet deployment after destroy/recreate

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TOTAL_TESTS=0

# Function to print test results
print_test_result() {
    local test_name="$1"
    local result="$2"
    local message="$3"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    if [ "$result" = "PASS" ]; then
        echo -e "${GREEN}✓ PASS${NC} - $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        if [ -n "$message" ]; then
            echo "  $message"
        fi
    else
        echo -e "${RED}✗ FAIL${NC} - $test_name"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        if [ -n "$message" ]; then
            echo -e "  ${RED}Error: $message${NC}"
        fi
    fi
    echo
}

# Function to test HTTP endpoint
test_http_endpoint() {
    local name="$1"
    local url="$2"
    local expected_status="$3"
    local timeout="${4:-10}"
    
    if curl -k -s --connect-timeout "$timeout" "$url" >/dev/null 2>&1; then
        if [ -n "$expected_status" ]; then
            response=$(curl -k -s "$url" 2>/dev/null)
            if echo "$response" | grep -q "$expected_status"; then
                print_test_result "$name" "PASS" "Endpoint responding with expected content"
            else
                print_test_result "$name" "FAIL" "Endpoint accessible but unexpected response"
            fi
        else
            print_test_result "$name" "PASS" "Endpoint accessible"
        fi
    else
        print_test_result "$name" "FAIL" "Endpoint not accessible or timeout"
    fi
}

# Function to test container status
test_container_status() {
    local container_name="$1"
    local expected_status="${2:-running}"
    
    if docker inspect "$container_name" >/dev/null 2>&1; then
        actual_status=$(docker inspect --format='{{.State.Status}}' "$container_name")
        if [ "$actual_status" = "$expected_status" ]; then
            print_test_result "Container $container_name" "PASS" "Status: $actual_status"
        else
            print_test_result "Container $container_name" "FAIL" "Expected: $expected_status, Got: $actual_status"
        fi
    else
        print_test_result "Container $container_name" "FAIL" "Container not found"
    fi
}

# Function to test Fleet agent status
test_agent_status() {
    local container_name="$1"
    local expected_fleet_status="$2"
    
    if status_output=$(docker exec "$container_name" elastic-agent status 2>/dev/null); then
        if echo "$status_output" | grep -q "$expected_fleet_status"; then
            print_test_result "$container_name Agent Status" "PASS" "Fleet status: $expected_fleet_status"
        else
            print_test_result "$container_name Agent Status" "FAIL" "Fleet status not as expected. Output: $status_output"
        fi
    else
        print_test_result "$container_name Agent Status" "FAIL" "Cannot get agent status"
    fi
}

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}   Fleet Deployment Test Suite${NC}"
echo -e "${BLUE}========================================${NC}"
echo

echo -e "${YELLOW}Phase 1: Container Health Checks${NC}"
echo "--------------------"

# Test core containers
test_container_status "vault-database_elasticsearch" "running"
test_container_status "vault-database_kibana" "running"
test_container_status "vault-database_fleet_server" "running"
test_container_status "vault-database_elastic_agent" "running"
test_container_status "vault-database_fleet_init" "exited"

echo -e "${YELLOW}Phase 2: Service Endpoint Tests${NC}"
echo "--------------------"

# Test service endpoints
test_http_endpoint "Elasticsearch HTTPS" "https://localhost:9200" "elasticsearch"
test_http_endpoint "Kibana HTTPS" "https://localhost:5601" "kibana"
test_http_endpoint "Fleet Server HTTP" "http://localhost:8220/api/status" "HEALTHY"

echo -e "${YELLOW}Phase 3: Fleet Token Validation${NC}"
echo "--------------------"

# Test Fleet tokens exist
if docker run --rm -v vault-database_fleet-tokens:/tokens alpine:latest test -f /tokens/fleet-server-token 2>/dev/null; then
    token_size=$(docker run --rm -v vault-database_fleet-tokens:/tokens alpine:latest wc -c < /tokens/fleet-server-token 2>/dev/null)
    if [ "$token_size" -gt 50 ]; then
        print_test_result "Fleet Server Token" "PASS" "Token exists and has valid size ($token_size bytes)"
    else
        print_test_result "Fleet Server Token" "FAIL" "Token too small ($token_size bytes)"
    fi
else
    print_test_result "Fleet Server Token" "FAIL" "Token file not found"
fi

if docker run --rm -v vault-database_fleet-tokens:/tokens alpine:latest test -f /tokens/enrollment-token 2>/dev/null; then
    token_size=$(docker run --rm -v vault-database_fleet-tokens:/tokens alpine:latest wc -c < /tokens/enrollment-token 2>/dev/null)
    if [ "$token_size" -gt 30 ]; then
        print_test_result "Enrollment Token" "PASS" "Token exists and has valid size ($token_size bytes)"
    else
        print_test_result "Enrollment Token" "FAIL" "Token too small ($token_size bytes)"
    fi
else
    print_test_result "Enrollment Token" "FAIL" "Token file not found"
fi

echo -e "${YELLOW}Phase 4: Agent Status Tests${NC}"
echo "--------------------"

# Test agent statuses
test_agent_status "vault-database_fleet_server" "Connected"

# For elastic-agent, we'll check if it's enrolled (post-deployment)
if status_output=$(docker exec vault-database_elastic_agent elastic-agent status 2>/dev/null); then
    if echo "$status_output" | grep -q "Connected"; then
        print_test_result "Elastic Agent Status" "PASS" "Agent is enrolled and connected"
    elif echo "$status_output" | grep -q "Not enrolled"; then
        print_test_result "Elastic Agent Status" "FAIL" "Agent not enrolled - run post-deployment script"
    else
        print_test_result "Elastic Agent Status" "FAIL" "Unexpected agent status: $status_output"
    fi
else
    print_test_result "Elastic Agent Status" "FAIL" "Cannot communicate with agent daemon"
fi

echo -e "${YELLOW}Phase 5: Kibana Fleet API Tests${NC}"
echo "--------------------"

# Test Fleet API
if agents_response=$(curl -k -s -X GET "https://localhost:5601/api/fleet/agents" \
    -H "kbn-xsrf: true" \
    -H "Content-Type: application/json" \
    -u "elastic:password123" \
    --cacert certs/ca/ca.crt 2>/dev/null); then
    
    agent_count=$(echo "$agents_response" | grep -o '"id"' | wc -l)
    online_count=$(echo "$agents_response" | grep -o '"status":"online"' | wc -l)
    
    if [ "$agent_count" -ge 1 ]; then
        print_test_result "Fleet API - Agent Registration" "PASS" "Found $agent_count registered agent(s)"
        
        if [ "$online_count" -ge 1 ]; then
            print_test_result "Fleet API - Online Agents" "PASS" "$online_count agent(s) online"
        else
            print_test_result "Fleet API - Online Agents" "FAIL" "No agents online (may need post-deployment script)"
        fi
    else
        print_test_result "Fleet API - Agent Registration" "FAIL" "No agents registered"
    fi
else
    print_test_result "Fleet API Access" "FAIL" "Cannot access Fleet API"
fi

echo -e "${YELLOW}Phase 6: Volume and Mount Tests${NC}"
echo "--------------------"

# Test volume mounts
if docker exec vault-database_elastic_agent test -d /mnt/vault-audit 2>/dev/null; then
    print_test_result "Vault Audit Volume Mount" "PASS" "Mount point exists"
else
    print_test_result "Vault Audit Volume Mount" "FAIL" "Mount point not found"
fi

if docker exec vault-database_elastic_agent test -d /tokens 2>/dev/null; then
    print_test_result "Fleet Tokens Volume Mount" "PASS" "Mount point exists"
else
    print_test_result "Fleet Tokens Volume Mount" "FAIL" "Mount point not found"
fi

echo -e "${YELLOW}Phase 7: Integration Readiness${NC}"
echo "--------------------"

# Test if ready for Vault integration
if docker exec vault-database_vault test -d /vault/audit 2>/dev/null; then
    print_test_result "Vault Audit Directory" "PASS" "Audit directory exists"
else
    print_test_result "Vault Audit Directory" "FAIL" "Audit directory not found"
fi

# Check if Vault is accessible
test_http_endpoint "Vault API" "http://localhost:8200/v1/sys/health" "initialized"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}           Test Summary${NC}"
echo -e "${BLUE}========================================${NC}"

echo -e "Total Tests: $TOTAL_TESTS"
echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
echo -e "${RED}Failed: $TESTS_FAILED${NC}"

if [ $TESTS_FAILED -eq 0 ]; then
    echo
    echo -e "${GREEN}🎉 ALL TESTS PASSED!${NC}"
    echo -e "${GREEN}Fleet deployment is fully functional.${NC}"
    echo
    echo "Next steps:"
    echo "1. If elastic-agent is not enrolled, run: ./post-deploy-fleet.sh"
    echo "2. Configure Vault audit logging"
    echo "3. Set up log collection in Fleet"
    exit 0
else
    echo
    echo -e "${RED}❌ Some tests failed.${NC}"
    echo "Review the failed tests above and check:"
    echo "1. All containers are running: docker-compose ps"
    echo "2. Check logs for failed services: docker-compose logs <service>"
    echo "3. Ensure certificates are properly mounted"
    echo "4. Run post-deployment script if enrollment failed"
    exit 1
fi