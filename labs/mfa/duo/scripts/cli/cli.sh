# Enable the Auth Method
vault auth enable userpass

# Get the accessor
vault auth list 
# accessor = auth_userpass_b0479be0

# Enable the secrets engine
vault secrets enable -path=secret kv-v2

# Create policy for specific resource access
vault policy write user-policy -<<EOF
path "secret/data/*" {
  capabilities = ["read", "create", "update"]
}
EOF

#Create the user and attach the policy
vault write auth/userpass/users/ajaypatel \
    password=testpassword \
    policies="default,duo-mfa-policy"

 # Create an identity entity for the user
vault write identity/entity \
    name="ajaypatel" \
    policies="default,duo-mfa-policy"   

# Read and note the entity id (id) cd87309f-61ea-d3e2-5652-fd1930729577
vault read identity/entity/name/ajaypatel

# create the alias 
vault write identity/entity-alias \
    name="ajaypatel" \
    canonical_id=cd87309f-61ea-d3e2-5652-fd1930729577 \
    mount_accessor=auth_userpass_d8cfb58e

#Verify the entiry has an alias
vault read identity/entity/name/ajaypatel

# Create  the MFA Method 
# Note the Accessor from the auth method in the username_format parameter
# OUtputs a method_id - this is required for the Login Enforcement

vault write identity/mfa/method/duo \
    integration_key=DI8DMHTQMD1TVLKH7WYT \
    secret_key=cTdGVF7vI76xCClHKVD41k2E95mKTtYD2qKprPHn \
    api_hostname=api-30e6f069.duosecurity.com \
    username_format="{{identity.entity.aliases.auth_userpass_d8cfb58e.name}}" 

# Create the Login Enforcement
# Requires method id from command above
vault write identity/mfa/login-enforcement/duo_enforcement \
    mfa_method_ids=edc0d675-f6ab-0ac2-ac2c-80a98faef27c \
    auth_method_accessors=auth_userpass_d8cfb58e

 # Test the Login 
 vault write auth/userpass/login/ajaypatel password=testpassword
 vault write auth/userpass/login/ajaypatel2 password=testpassword

############ END CONFIG

#Secrets
# Create test secret
vault kv put secret/foo data="MFA protected data"
# Create user-specific secret
vault kv put secret/ajaypatel/personal data="User personal data"
# Create shared secret
vault kv put secret/shared/company data="Company shared information"


#GET all Entity ID
 vault list identity/entity/id
 #Read the Entity Id via the Id
 vault read identity/entity/id/2e3e0b2e-92d3-7e97-3c9a-89dd6474d734
 # Read the entity via the username
 vault read identity/entity/name/ajaypatel



