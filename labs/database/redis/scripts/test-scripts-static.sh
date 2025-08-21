#READ THE ROLE
vault read database/redis/my-redis-application/static-creds/vault-static-user-1-role 
vault read database/redis/my-redis-application/static-creds/vault-static-user-2-role 
vault read database/redis/my-redis-application/static-creds/vault-static-user-3-role  

#LIST THE POLICIES 
vault policy list 
vault policy list -format=json
#GET DETAILED INFOR FOR ALL POLICIES
vault policy list | xargs -I {} vault policy read {} 

# READ A SINGLE POLICY
vault policy read redis-vault-static-user-1-reader-policy

