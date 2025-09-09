#!/bin/bash
# vault-elk-debug.sh
# Comprehensive debugging script for Vault to ELK log integration

set -e

echo "========================================"
echo "Vault to ELK Integration Debug Script"
echo "========================================"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

debug_section() {
    echo -e "\n${BLUE}=== $1 ===${NC}"
}

check_status() {
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ $1${NC}"
    else
        echo -e "${RED}✗ $1${NC}"
    fi
}

debug_section "1. Container Status Check"
echo "Checking all containers are running..."

CONTAINERS=("vault" "elasticsearch" "kibana" "fleet-server" "elastic-agent")
for container in "${CONTAINERS[@]}"; do
    if docker ps --format "table {{.Names}}" | grep -q "${COMPOSE_PROJECT_NAME:-vault-database}_${container}"; then
        echo -e "${GREEN}✓ ${container} is running${NC}"
    else
        echo -e "${RED}✗ ${container} is not running${NC}"
        echo "Available containers:"
        docker ps --format "table {{.Names}}"
    fi
done

debug_section "2. Vault Audit Configuration Check"
echo "Checking Vault audit device configuration..."

# Check if Vault is initialized and unsealed
echo "Vault status:"
if docker exec vault-database_vault vault status 2>/dev/null; then
    check_status "Vault is accessible"
    
    echo -e "\nChecking audit devices:"
    docker exec vault-database_vault vault audit list 2>/dev/null || echo "Failed to list audit devices"
    
    echo -e "\nChecking audit directory permissions:"
    docker exec vault-database_vault ls -la /vault/audit/ 2>/dev/null || echo "Audit directory not accessible"
    
    echo -e "\nChecking if audit log file exists:"
    docker exec vault-database_vault ls -la /vault/audit/vault_audit.log 2>/dev/null || echo "Audit log file not found"
    
    echo -e "\nChecking audit log file size and recent entries:"
    docker exec vault-database_vault wc -l /vault/audit/vault_audit.log 2>/dev/null || echo "Cannot read audit log file"
    echo "Last 3 lines of audit log:"
    docker exec vault-database_vault tail -n 3 /vault/audit/vault_audit.log 2>/dev/null || echo "Cannot tail audit log file"
else
    echo -e "${RED}✗ Vault is not accessible${NC}"
fi

debug_section "3. Volume Mount Verification"
echo "Checking volume mounts between Vault and Elastic Agent..."

echo "Vault audit volume mount:"
docker inspect vault-database_vault | jq -r '.[0].Mounts[] | select(.Destination == "/vault/audit") | "Source: \(.Source), Destination: \(.Destination), Type: \(.Type)"' 2>/dev/null || echo "Mount info not available"

echo -e "\nElastic Agent audit volume mount:"
docker inspect vault-database_elastic_agent | jq -r '.[0].Mounts[] | select(.Destination == "/mnt/vault-audit") | "Source: \(.Source), Destination: \(.Destination), Type: \(.Type)"' 2>/dev/null || echo "Mount info not available"

echo -e "\nChecking if Elastic Agent can see Vault audit logs:"
docker exec vault-database_elastic_agent ls -la /mnt/vault-audit/ 2>/dev/null || echo "Elastic Agent cannot access audit directory"
docker exec vault-database_elastic_agent cat /mnt/vault-audit/vault_audit.log 2>/dev/null | head -n 3 || echo "Elastic Agent cannot read audit log file"

debug_section "4. Fleet and Elastic Agent Status"
echo "Checking Fleet Server status..."
curl -s http://localhost:8220/api/status 2>/dev/null && echo -e "${GREEN}✓ Fleet Server is responding${NC}" || echo -e "${RED}✗ Fleet Server is not responding${NC}"

echo -e "\nChecking Elastic Agent enrollment status:"
docker exec vault-database_elastic_agent elastic-agent status 2>/dev/null || echo "Cannot get elastic agent status"

echo -e "\nChecking agents in Kibana Fleet:"
AGENTS_RESPONSE=$(curl -k -s -X GET "https://localhost:5601/api/fleet/agents" \
    -H "kbn-xsrf: true" \
    -H "Content-Type: application/json" \
    -u "elastic:password123" \
    --cacert certs/ca/ca.crt 2>/dev/null)

if [ $? -eq 0 ] && echo "$AGENTS_RESPONSE" | jq empty 2>/dev/null; then
    echo "Agents found in Fleet:"
    echo "$AGENTS_RESPONSE" | jq -r '.list[] | "  ID: \(.id) | Status: \(.status) | Policy: \(.policy_id)"' 2>/dev/null
else
    echo "Failed to retrieve agents from Kibana Fleet"
fi

debug_section "5. Integration Configuration Check"
echo "Checking Vault integration in Kibana..."

PACKAGE_POLICIES=$(curl -k -s -X GET "https://localhost:5601/api/fleet/package_policies" \
    -H "kbn-xsrf: true" \
    -H "Content-Type: application/json" \
    -u "elastic:password123" \
    --cacert certs/ca/ca.crt 2>/dev/null)

if echo "$PACKAGE_POLICIES" | jq empty 2>/dev/null; then
    echo "Package policies found:"
    echo "$PACKAGE_POLICIES" | jq -r '.items[] | select(.package.name == "hashicorp_vault") | "  Name: \(.name) | Package: \(.package.name) | Version: \(.package.version)"' 2>/dev/null || echo "No Vault package policies found"
    
    echo -e "\nVault integration details:"
    echo "$PACKAGE_POLICIES" | jq '.items[] | select(.package.name == "hashicorp_vault") | .inputs[0].streams[0].vars.paths.value' 2>/dev/null || echo "Cannot extract path configuration"
else
    echo "Failed to retrieve package policies"
fi

debug_section "6. Elasticsearch Index Check"
echo "Checking for Vault-related indices in Elasticsearch..."

INDICES=$(curl -k -s -X GET "https://localhost:9200/_cat/indices/logs-hashicorp_vault*?v" \
    -u "elastic:password123" \
    --cacert certs/ca/ca.crt 2>/dev/null)

if [ $? -eq 0 ] && [ ! -z "$INDICES" ]; then
    echo "Vault-related indices found:"
    echo "$INDICES"
else
    echo "No Vault-related indices found"
fi

echo -e "\nChecking for any log indices:"
curl -k -s -X GET "https://localhost:9200/_cat/indices/logs-*?v" \
    -u "elastic:password123" \
    --cacert certs/ca/ca.crt 2>/dev/null || echo "Failed to retrieve log indices"

echo -e "\nDocument count in Vault audit indices:"
curl -k -s -X GET "https://localhost:9200/logs-hashicorp_vault.audit-*/_count" \
    -H "Content-Type: application/json" \
    -u "elastic:password123" \
    --cacert certs/ca/ca.crt 2>/dev/null | jq '.count' 2>/dev/null || echo "No documents found or index doesn't exist"

debug_section "7. Log File Analysis"
echo "Analyzing Elastic Agent logs for errors..."

echo "Recent Elastic Agent logs (last 20 lines):"
docker logs vault-database_elastic_agent --tail 20 2>/dev/null || echo "Cannot retrieve Elastic Agent logs"

echo -e "\nSearching for errors in Elastic Agent logs:"
docker logs vault-database_elastic_agent 2>&1 | grep -i error | tail -10 2>/dev/null || echo "No errors found in recent logs"

echo -e "\nSearching for Vault-related entries in Elastic Agent logs:"
docker logs vault-database_elastic_agent 2>&1 | grep -i vault | tail -5 2>/dev/null || echo "No Vault-related entries found"

debug_section "8. Manual Log Generation Test"
echo "Generating test Vault operations to create audit logs..."

if docker exec vault-database_vault vault status >/dev/null 2>&1; then
    echo "Creating test secret..."
    docker exec vault-database_vault vault kv put secret/debug-test timestamp="$(date)" test=true 2>/dev/null && echo "✓ Secret created" || echo "✗ Failed to create secret"
    
    echo "Reading test secret..."
    docker exec vault-database_vault vault kv get secret/debug-test 2>/dev/null && echo "✓ Secret read" || echo "✗ Failed to read secret"
    
    echo "Deleting test secret..."
    docker exec vault-database_vault vault kv delete secret/debug-test 2>/dev/null && echo "✓ Secret deleted" || echo "✗ Failed to delete secret"
    
    echo -e "\nWaiting 30 seconds for logs to be processed..."
    sleep 30
    
    echo "Checking if new audit entries were created:"
    docker exec vault-database_vault tail -n 5 /vault/audit/vault_audit.log 2>/dev/null | grep "$(date +%Y-%m-%d)" || echo "No recent audit entries found"
else
    echo "Cannot perform test operations - Vault not accessible"
fi

debug_section "9. Troubleshooting Recommendations"
echo -e "${YELLOW}Based on the checks above, here are potential issues and solutions:${NC}"

echo -e "\n${YELLOW}Common Issues:${NC}"
echo "1. Vault audit device not enabled:"
echo "   Solution: docker exec vault-database_vault vault audit enable -path=audit_log file file_path=/vault/audit/vault_audit.log"

echo -e "\n2. Permission issues with audit log file:"
echo "   Solution: docker exec vault-database_vault chown vault:vault /vault/audit"

echo -e "\n3. Elastic Agent not enrolled or not connected:"
echo "   Solution: Re-run the complete-fleet-vault-setup.sh script"

echo -e "\n4. Volume mount issues:"
echo "   Solution: Check docker-compose.yml volume mappings for vault-audit-logs"

echo -e "\n5. Integration configuration incorrect:"
echo "   Solution: Verify the log path in Fleet integration matches /mnt/vault-audit/vault_audit.log"

echo -e "\n6. Fleet output not configured for HTTPS:"
echo "   Solution: Ensure Fleet output is configured with proper SSL settings"

echo -e "\n${YELLOW}Next Steps:${NC}"
echo "1. Fix any issues identified above"
echo "2. Restart the affected containers: docker-compose restart elastic-agent vault"
echo "3. Wait 5-10 minutes for log collection to stabilize"
echo "4. Check Elasticsearch again: curl -k https://localhost:9200/logs-hashicorp_vault.audit-*/_count -u elastic:password123 --cacert certs/ca/ca.crt"

echo -e "\n========================================"
echo "Debug script completed!"
echo "========================================"