ls -la ./certs/
ls -la ./certs/ca/ 2>/dev/null || echo "ca directory not found"
ls -la ./certs/elasticsearch/ 2>/dev/null || echo "elasticsearch directory not found"

# Or find all certificate files
find ./certs -name "*.crt" -o -name "*.key"


docker exec -e VAULT_ADDR='http://localhost:8200' -e VAULT_TOKEN='hvs.U0cIlhJPrYzonwzVGb4KZo1V' mohre_vault vault write database/config/my-elasticsearch-database \
    plugin_name="elasticsearch-database-plugin" \
    url="https://localhost:9200" \
    username="elastic" \
    password="password123" \
    ca_cert=@/vault/certs/ca/ca.crt \
    client_cert=@/vault/certs/elasticsearch/elasticsearch.crt \
    client_key=@/vault/certs/elasticsearch/elasticsearch.key \
    allowed_roles="my-role"

docker exec -e VAULT_ADDR='http://localhost:8200' -e VAULT_TOKEN='hvs.U0cIlhJPrYzonwzVGb4KZo1V' mohre_vault vault write database/config/my-elasticsearch-database \
    plugin_name="elasticsearch-database-plugin" \
    url="https://localhost:9200" \
    username="elastic" \
    password="password123" \
    ca_file="/vault/certs/ca/ca.crt" \
    cert_file="/vault/certs/elasticsearch/elasticsearch.crt" \
    key_file="/vault/certs/elasticsearch/elasticsearch.key" \
    allowed_roles="my-role"

docker inspect docker-elk-tls_elastic-network | grep IPAddress

docker exec -e VAULT_ADDR='http://localhost:8200' -e VAULT_TOKEN='hvs.U0cIlhJPrYzonwzVGb4KZo1V' mohre_vault vault write database/config/my-elasticsearch-database \
    plugin_name="elasticsearch-database-plugin" \
    url="https://elasticsearch:9200" \
    username="elastic" \
    password="password123" \
    tls_skip_verify=true \
    allowed_roles="my-role"