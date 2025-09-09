
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
