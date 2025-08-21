#LIST ALL ROLES ON THE MOUNT
vault list database/redis/my-redis-application/roles

#READ THE ROLE
vault read database/redis/my-redis-application/roles/my-redis-application-dynamic-admin-role

vault read database/redis/my-redis-application/roles/my-redis-application-dynamic-readonly-role

#CREATE CREDS AGAINST EACH ROLE

vault read database/redis/my-redis-application/creds/my-redis-application-dynamic-admin-role

vault read database/redis/my-redis-application/creds/my-redis-application-dynamic-readonly-role


# VIEW ALL cuurnet leases 
vault list  -format=json sys/leases/lookup/database/redis/my-redis-application/role/my-redis-application-dynamic-admin-role | jq -r '.[]' | xargs -I {} vault lease lookup  database/redis/my-redis-application/creds/role/my-redis-application-dynamic-admin-role

# MIGHT HAVE TO FORCE IF LEASES STILL EXIST
vault lease revoke -f database/redis/creds/redis-dynamic-role/<leaseid>
vault lease revoke -force -prefix database/
vault lease revoke -force -prefix database/redis

# To Renew a Lease on a dynamic credential
# Step 1 - Create the Credential and Note the "lease_id" 
vault read database/redis/my-redis-application/creds/my-redis-application-dynamic-admin-role
# Step 2a - Run the "lease renew" command with the full lease id
vault lease renew database/redis/my-redis-application/creds/my-redis-application-dynamic-admin-role/D1PbN10QZlxyS9eeUk3Q3X7i
# Step 2b - Run the "lease renew" command with the full lease id 
# Add increment to renew for longer that the default we set (default_ttl)
# NOTE that the increment cannot exceed the max_ttl we set
vault lease renew -increment=1000 database/redis/my-redis-application/creds/my-redis-application-dynamic-admin-role/D1PbN10QZlxyS9eeUk3Q3X7i