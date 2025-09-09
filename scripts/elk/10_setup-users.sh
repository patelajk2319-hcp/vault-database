#!/bin/sh
set -e

echo "=== Elasticsearch User Setup with TLS ==="

# Wait for Elasticsearch to be ready
echo "⏳ Waiting for Elasticsearch to be ready..."
sleep 15

# Test HTTPS connection
echo "🔍 Testing HTTPS connection to Elasticsearch..."
if ! curl -s --cacert /certs/ca.crt -u "elastic:password123" "https://elasticsearch:9200/_cluster/health" > /dev/null; then
    echo "❌ Cannot connect to Elasticsearch via HTTPS. Retrying..."
    sleep 30
    if ! curl -s --cacert /certs/ca.crt -u "elastic:password123" "https://elasticsearch:9200/_cluster/health" > /dev/null; then
        echo "❌ Still cannot connect to Elasticsearch. Exiting."
        exit 1
    fi
fi

echo "✅ HTTPS connection successful!"

# Set kibana_system password
echo "🔐 Setting kibana_system password..."
curl -X POST "https://elasticsearch:9200/_security/user/kibana_system/_password" \
  -H "Content-Type: application/json" \
  --cacert /certs/ca.crt \
  -u "elastic:password123" \
  -d '{"password": "kibana_password123"}'

echo ""
echo "✅ kibana_system password set"

# Create kibana admin user
echo "👤 Creating kibana_admin user..."
curl -X POST "https://elasticsearch:9200/_security/user/kibana_admin" \
  -H "Content-Type: application/json" \
  --cacert /certs/ca.crt \
  -u "elastic:password123" \
  -d '{
    "password": "kibana_admin123",
    "roles": ["kibana_admin", "superuser"],
    "full_name": "Kibana Administrator",
    "email": "kibana-admin@elastic.local"
  }'

echo "✅ kibana_admin user created"

# Create vault users
echo "🔐 Creating vault users..."
curl -X POST "https://elasticsearch:9200/_security/user/vault-static-user-1" \
  -H "Content-Type: application/json" \
  --cacert /certs/ca.crt \
  -u "elastic:password123" \
  -d '{
    "password": "vault_password123",
    "roles": ["kibana_user"],
    "full_name": "Vault Static User 1",
    "email": "vault-user@vault.local"
  }'

curl -X POST "https://elasticsearch:9200/_security/user/vault-static-user-2" \
  -H "Content-Type: application/json" \
  --cacert /certs/ca.crt \
  -u "elastic:password123" \
  -d '{
    "password": "vault_password456",
    "roles": ["kibana_user"],
    "full_name": "Vault Static User 2",
    "email": "vault-user2@vault.local"
  }'

  curl -X POST "https://elasticsearch:9200/_security/user/vault-static-user-3" \
  -H "Content-Type: application/json" \
  --cacert /certs/ca.crt \
  -u "elastic:password123" \
  -d '{
    "password": "vault_password456",
    "roles": ["kibana_user"],
    "full_name": "Vault Static User 3",
    "email": "vault-user3@vault.local"
  }'

# Create read-only user
curl -X POST "https://elasticsearch:9200/_security/user/readonly-user" \
  -H "Content-Type: application/json" \
  --cacert /certs/ca.crt \
  -u "elastic:password123" \
  -d '{
    "password": "readonly_password123",
    "roles": ["viewer"],
    "full_name": "Read Only User",
    "email": "readonly@elastic.local"
  }'

echo ""
echo "🎉 User setup completed!"
echo ""
echo "=== CREATED USERS ==="
echo "👑 Admin Users:"
echo "   • elastic (superuser): password123"
echo "   • kibana_admin (web login): kibana_admin123"
echo ""
echo "🏦 Application Users:"
echo "   • vault-static-user-1: vault_password123"
echo "   • vault-static-user-2: vault_password456"
echo "   • readonly-user: readonly_password123"