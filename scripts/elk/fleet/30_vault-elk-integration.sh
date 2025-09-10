#!/bin/bash
# scripts/elk/install-vault-integration.sh
# Standalone script to install HashiCorp Vault integration in Fleet

set -e

# Color definitions
GREEN='\033[0;32m'    # Green text for success messages
YELLOW='\033[1;33m'   # Yellow text for warnings
BLUE='\033[0;34m'     # Blue text for informational messages
NC='\033[0m'          # No Color - resets text color to default

# Source .env file if it exists to get VAULT_TOKEN
if [ -f ".env" ]; then
    echo -e "${BLUE}Loading environment variables from .env file...${NC}"
    source .env
fi

# Configuration - can be overridden via environment variables
KIBANA_HOST="${KIBANA_HOST:-https://localhost:5601}"
KIBANA_USER="${KIBANA_USER:-elastic}"
KIBANA_PASSWORD="${KIBANA_PASSWORD:-password123}"
CA_CERT="${CA_CERT:-./certs/ca/ca.crt}"
VAULT_TOKEN="${VAULT_TOKEN:-}"

echo -e "${BLUE}=== Installing HashiCorp Vault Integration ===${NC}"

if [ -n "$VAULT_TOKEN" ]; then
    echo -e "${BLUE}Vault token detected - will attempt to include metrics${NC}"
    echo -e "${BLUE}Token: ${VAULT_TOKEN:0:10}...${NC}"
else
    echo -e "${BLUE}No Vault token provided - installing logs only${NC}"
    echo -e "${BLUE}Set VAULT_TOKEN environment variable to enable metrics${NC}"
fi

# Check if Kibana is accessible
echo -e "${BLUE}Checking Kibana connectivity...${NC}"
if ! curl -k -s --fail --cacert "$CA_CERT" -u "$KIBANA_USER:$KIBANA_PASSWORD" \
   "$KIBANA_HOST/api/status" > /dev/null 2>&1; then
    echo -e "${YELLOW}ERROR: Cannot connect to Kibana at $KIBANA_HOST${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Kibana is accessible${NC}"

# Get the Default Agent Policy ID
echo -e "${BLUE}Finding Default Agent Policy...${NC}"
POLICY_RESPONSE=$(curl -k -s -X GET "$KIBANA_HOST/api/fleet/agent_policies" \
  -H "kbn-xsrf: true" \
  -H "Content-Type: application/json" \
  -u "$KIBANA_USER:$KIBANA_PASSWORD" \
  --cacert "$CA_CERT")

POLICY_ID=$(echo "$POLICY_RESPONSE" | grep -o '"id":"[^"]*"[^}]*"name":"Default Agent Policy"' | head -1 | grep -o '"id":"[^"]*"' | cut -d'"' -f4)

if [ -z "$POLICY_ID" ]; then
    echo -e "${YELLOW}ERROR: Could not find Default Agent Policy${NC}"
    echo -e "${BLUE}Available policies:${NC}"
    echo "$POLICY_RESPONSE" | grep -o '"name":"[^"]*"' || echo "No policies found"
    exit 1
fi

echo -e "${GREEN}✓ Found Default Agent Policy ID: $POLICY_ID${NC}"

# Check if Vault integration already exists
echo -e "${BLUE}Checking if Vault integration already exists...${NC}"
EXISTING_INTEGRATION=$(curl -k -s -X GET "$KIBANA_HOST/api/fleet/package_policies" \
  -H "kbn-xsrf: true" \
  -H "Content-Type: application/json" \
  -u "$KIBANA_USER:$KIBANA_PASSWORD" \
  --cacert "$CA_CERT" | grep -o '"name":"hashicorp_vault-[^"]*"' | head -1)

if [ -n "$EXISTING_INTEGRATION" ]; then
    echo -e "${YELLOW}⚠️  Vault integration already exists: $EXISTING_INTEGRATION${NC}"
    echo -e "${BLUE}To reinstall, first remove the existing integration from Kibana Fleet UI${NC}"
    exit 0
fi

# Install HashiCorp Vault package
echo -e "${BLUE}Installing HashiCorp Vault package...${NC}"
PACKAGE_RESPONSE=$(curl -k -s -X POST "$KIBANA_HOST/api/fleet/epm/packages/hashicorp_vault" \
  -H "kbn-xsrf: true" \
  -H "Content-Type: application/json" \
  -u "$KIBANA_USER:$KIBANA_PASSWORD" \
  --cacert "$CA_CERT")

if echo "$PACKAGE_RESPONSE" | grep -q "error"; then
    echo -e "${BLUE}Package installation response: $PACKAGE_RESPONSE${NC}"
    echo -e "${YELLOW}⚠️  Package may already be installed${NC}"
else
    echo -e "${GREEN}✓ Vault package installed${NC}"
fi

sleep 3

# Function to create integration with metrics
create_integration_with_metrics() {
    echo -e "${BLUE}Attempting to create integration with metrics enabled...${NC}"
    
    curl -k -s -X POST "$KIBANA_HOST/api/fleet/package_policies" \
      -H "kbn-xsrf: true" \
      -H "Content-Type: application/json" \
      -u "$KIBANA_USER:$KIBANA_PASSWORD" \
      --cacert "$CA_CERT" \
      -d "{
        \"name\": \"hashicorp_vault-1\",
        \"description\": \"HashiCorp Vault integration for audit logs, operational logs, and metrics\",
        \"namespace\": \"default\",
        \"policy_id\": \"$POLICY_ID\",
        \"package\": {
          \"name\": \"hashicorp_vault\",
          \"version\": \"1.28.1\"
        },
        \"inputs\": [
          {
            \"type\": \"logfile\",
            \"policy_template\": \"log\",
            \"enabled\": true,
            \"streams\": [
              {
                \"id\": \"logfile-hashicorp_vault.audit-$POLICY_ID\",
                \"enabled\": true,
                \"data_stream\": {
                  \"type\": \"logs\",
                  \"dataset\": \"hashicorp_vault.audit\"
                },
                \"vars\": {
                  \"paths\": {
                    \"value\": [\"/mnt/vault-logs/*.log\"],
                    \"type\": \"text\"
                  },
                  \"tags\": {
                    \"value\": [\"hashicorp-vault-audit\"],
                    \"type\": \"text\"
                  },
                  \"exclude_files\": {
                    \"value\": [\"\\\\.gz$\"],
                    \"type\": \"text\"
                  },
                  \"preserve_original_event\": {
                    \"value\": false,
                    \"type\": \"bool\"
                  }
                }
              },
              {
                \"id\": \"logfile-hashicorp_vault.log-$POLICY_ID\",
                \"enabled\": true,
                \"data_stream\": {
                  \"type\": \"logs\",
                  \"dataset\": \"hashicorp_vault.log\"
                },
                \"vars\": {
                  \"paths\": {
                    \"value\": [\"/mnt/vault-logs/*.json\"],
                    \"type\": \"text\"
                  },
                  \"tags\": {
                    \"value\": [\"hashicorp-vault-log\"],
                    \"type\": \"text\"
                  },
                  \"exclude_files\": {
                    \"value\": [\"\\\\.gz$\"],
                    \"type\": \"text\"
                  },
                  \"preserve_original_event\": {
                    \"value\": false,
                    \"type\": \"bool\"
                  }
                }
              }
            ]
          },
          {
            \"type\": \"prometheus/metrics\",
            \"policy_template\": \"metrics\",
            \"enabled\": true,
            \"streams\": [
              {
                \"id\": \"prometheus/metrics-hashicorp_vault.metrics-$POLICY_ID\",
                \"enabled\": true,
                \"data_stream\": {
                  \"type\": \"metrics\",
                  \"dataset\": \"hashicorp_vault.metrics\"
                },
                \"vars\": {
                  \"hosts\": {
                    \"value\": [\"http://vault:8200\"],
                    \"type\": \"text\"
                  },
                  \"metrics_path\": {
                    \"value\": \"/v1/sys/metrics\",
                    \"type\": \"text\"
                  },
                  \"period\": {
                    \"value\": \"30s\",
                    \"type\": \"text\"
                  },
                  \"query\": {
                    \"value\": {\"format\": \"prometheus\"},
                    \"type\": \"yaml\"
                  },
                  \"vault_token\": {
                    \"value\": \"$VAULT_TOKEN\",
                    \"type\": \"password\"
                  }
                }
              }
            ]
          }
        ]
      }"
}

# Function to create integration without metrics (fallback)
create_integration_logs_only() {
    echo -e "${BLUE}Creating integration with logs only...${NC}"
    
    curl -k -s -X POST "$KIBANA_HOST/api/fleet/package_policies" \
      -H "kbn-xsrf: true" \
      -H "Content-Type: application/json" \
      -u "$KIBANA_USER:$KIBANA_PASSWORD" \
      --cacert "$CA_CERT" \
      -d "{
        \"name\": \"hashicorp_vault-1\",
        \"description\": \"HashiCorp Vault integration for audit and operational logs\",
        \"namespace\": \"default\",
        \"policy_id\": \"$POLICY_ID\",
        \"package\": {
          \"name\": \"hashicorp_vault\",
          \"version\": \"1.28.1\"
        },
        \"inputs\": [
          {
            \"type\": \"logfile\",
            \"policy_template\": \"log\",
            \"enabled\": true,
            \"streams\": [
              {
                \"id\": \"logfile-hashicorp_vault.audit-$POLICY_ID\",
                \"enabled\": true,
                \"data_stream\": {
                  \"type\": \"logs\",
                  \"dataset\": \"hashicorp_vault.audit\"
                },
                \"vars\": {
                  \"paths\": {
                    \"value\": [\"/mnt/vault-logs/*.log\"],
                    \"type\": \"text\"
                  },
                  \"tags\": {
                    \"value\": [\"hashicorp-vault-audit\"],
                    \"type\": \"text\"
                  },
                  \"exclude_files\": {
                    \"value\": [\"\\\\.gz$\"],
                    \"type\": \"text\"
                  },
                  \"preserve_original_event\": {
                    \"value\": false,
                    \"type\": \"bool\"
                  }
                }
              },
              {
                \"id\": \"logfile-hashicorp_vault.log-$POLICY_ID\",
                \"enabled\": true,
                \"data_stream\": {
                  \"type\": \"logs\",
                  \"dataset\": \"hashicorp_vault.log\"
                },
                \"vars\": {
                  \"paths\": {
                    \"value\": [\"/mnt/vault-logs/*.json\"],
                    \"type\": \"text\"
                  },
                  \"tags\": {
                    \"value\": [\"hashicorp-vault-log\"],
                    \"type\": \"text\"
                  },
                  \"exclude_files\": {
                    \"value\": [\"\\\\.gz$\"],
                    \"type\": \"text\"
                  },
                  \"preserve_original_event\": {
                    \"value\": false,
                    \"type\": \"bool\"
                  }
                }
              }
            ]
          }
        ]
      }"
}

# Try to create integration with or without metrics based on token availability
METRICS_ENABLED=false
if [ -n "$VAULT_TOKEN" ]; then
    INTEGRATION_RESPONSE=$(create_integration_with_metrics)
    
    if echo "$INTEGRATION_RESPONSE" | grep -q "\"id\""; then
        METRICS_ENABLED=true
        echo -e "${GREEN}✓ Integration created successfully with metrics enabled${NC}"
    else
        echo -e "${YELLOW}⚠️  Failed to create integration with metrics, trying logs-only...${NC}"
        echo -e "${BLUE}Metrics error: $(echo "$INTEGRATION_RESPONSE" | grep -o '"message":"[^"]*"')${NC}"
        INTEGRATION_RESPONSE=$(create_integration_logs_only)
    fi
else
    INTEGRATION_RESPONSE=$(create_integration_logs_only)
fi

# Check final result
if echo "$INTEGRATION_RESPONSE" | grep -q "\"id\""; then
    INTEGRATION_ID=$(echo "$INTEGRATION_RESPONSE" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
    echo -e "${GREEN}✓ HashiCorp Vault integration created successfully!${NC}"
    echo -e "${BLUE}Integration ID: $INTEGRATION_ID${NC}"
    echo -e "${BLUE}Policy ID: $POLICY_ID${NC}"
else
    echo -e "${YELLOW}❌ Failed to create HashiCorp Vault integration${NC}"
    echo -e "${BLUE}Response: $INTEGRATION_RESPONSE${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}=== Integration Installation Complete ===${NC}"
echo ""
echo -e "${BLUE}Configuration:${NC}"
echo -e "${BLUE}- Audit logs: /mnt/vault-logs/*.log${NC}"
echo -e "${BLUE}- Operation logs: /mnt/vault-logs/*.json${NC}"

if [ "$METRICS_ENABLED" = true ]; then
    echo -e "${GREEN}- Metrics: Enabled (http://vault:8200)${NC}"
    echo -e "${BLUE}- Vault token: ${VAULT_TOKEN:0:10}... (configured)${NC}"
else
    echo -e "${BLUE}- Metrics: Disabled${NC}"
    if [ -n "$VAULT_TOKEN" ]; then
        echo -e "${YELLOW}  (Token provided but metrics validation failed - can be enabled manually in Kibana)${NC}"
    else
        echo -e "${BLUE}  (No VAULT_TOKEN provided - can be enabled manually in Kibana)${NC}"
    fi
fi

echo ""
echo -e "${BLUE}Next steps:${NC}"
echo -e "${BLUE}1. Wait 1-2 minutes for the agent to receive the new policy${NC}"
echo -e "${BLUE}2. Generate Vault activity to create audit logs:${NC}"
echo -e "${BLUE}   docker exec vault-database_vault vault kv put secret/test key=value${NC}"
echo -e "${BLUE}   docker exec vault-database_vault vault kv get secret/test${NC}"
echo -e "${BLUE}3. Check logs in Kibana Discover: logs-hashicorp_vault.audit-*${NC}"

if [ "$METRICS_ENABLED" = true ]; then
    echo -e "${BLUE}4. Check metrics in Kibana Discover: metrics-hashicorp_vault.metrics-*${NC}"
fi

if [ "$METRICS_ENABLED" = false ] && [ -n "$VAULT_TOKEN" ]; then
    echo ""
    echo -e "${BLUE}To manually enable metrics:${NC}"
    echo -e "${BLUE}- Go to Fleet -> Agent policies -> Default Agent Policy${NC}"
    echo -e "${BLUE}- Edit the HashiCorp Vault integration${NC}"
    echo -e "${BLUE}- Enable the metrics input and add your Vault token${NC}"
fi

echo ""
echo -e "${BLUE}Verification commands:${NC}"
echo -e "${BLUE}- Check agent status: docker exec vault-database_elastic_agent elastic-agent status${NC}"
echo -e "${BLUE}- Check for indices: curl -k -u elastic:password123 'https://localhost:9200/_cat/indices/logs-vault*?v' --cacert ./certs/ca/ca.crt${NC}"