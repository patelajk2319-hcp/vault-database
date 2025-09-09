
#configure the plugin - not cert vailidate
vault write database/config/my-elasticsearch-database \
  plugin_name="elasticsearch-database-plugin" \
  url="https://elasticsearch:9200" \
  username="elastic" \
  password="password123" \
  insecure=true \
  allowed_roles="my-role"

#configure the plugin =  cert validation
vault write database/config/my-elasticsearch-database \
  plugin_name="elasticsearch-database-plugin" \
  url="https://elasticsearch:9200" \
  username="elastic" \
  password="password123" \
  ca_cert="/vault/ca.crt" \
  allowed_roles="my-dynamic-role, my-static-role"


# create the role to create dynamic creds
vault write database/roles/my-dynamic-role\
      db_name=my-elasticsearch-database \
      creation_statements='{"elasticsearch_role_definition": {"indices": [{"names":["*"], "privileges":["read"]}]}}' \
      default_ttl="1h" \
      max_ttl="24h"
 
 # create the dynamic cred
 vault read database/creds/my-dynamic-role

 # static creds
 vault write database/static-roles/my-static-role\
      db_name=my-elasticsearch-database \
      username=vault-static-user-1 \
      rotation_period="24h"

vault read database/static-creds/my-static-role

#view plugin details

vault read database/elk/my-elk-application/config/my-elk-database   

# Roate root
vault write -f database/rotate-root/my-elk-database 


docker run -d \
  --name vault-database_fleet_server \
  --network vault-database_default \
  -p 8220:8220 \
  -e FLEET_SERVER_ENABLE=1 \
  -e FLEET_SERVER_ELASTICSEARCH_HOST=https://elasticsearch:9200 \
  -e FLEET_SERVER_SERVICE_TOKEN=AAEAAWVsYXN0aWMvZmxlZXQtc2VydmVyL3Rva2VuLTE3NTczMzgxMjk3NTk6cnhRWmR2aGNUVWFHcWd3bWoyMVNydw \
  -e FLEET_SERVER_POLICY_ID=fleet-server-policy \
  -e FLEET_SERVER_HOST=0.0.0.0 \
  -e FLEET_SERVER_PORT=8220 \
  -e FLEET_SERVER_ELASTICSEARCH_USERNAME=elastic \
  -e FLEET_SERVER_ELASTICSEARCH_PASSWORD=password123 \
  -e FLEET_SERVER_ELASTICSEARCH_CA=/certs/ca.crt \
  -e FLEET_SERVER_INSECURE_HTTP=true \
  -e FLEET_URL=http://fleet-server:8220 \
  -v $(pwd)/certs/ca/ca.crt:/certs/ca.crt:ro \
  --restart unless-stopped \
  docker.elastic.co/beats/elastic-agent:8.12.0

  docker exec vault-database_elastic_agent elastic-agent status

  curl -k http://localhost:8220/api/status   