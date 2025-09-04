# Configure the Authentication Backend
resource "vault_auth_backend" "userpass" {
  type = "userpass"
  path = "userpass"
}

# Create Vault MFA Policy
data "vault_policy_document" "duo_mfa_policy" {
  rule {
    path         = "secret/data/*" # in kv-v2 all secrets are stored in this path
    capabilities = ["read", "create", "update"]
    description  = "Allows read, create, and update access to secret data"
  }
}

resource "vault_policy" "duo_mfa_policy" {
  name   = "duo-mfa-policy"
  policy = data.vault_policy_document.duo_mfa_policy.hcl
}

# Create userpass user - this exists in Duo
resource "vault_generic_secret" "user" {
  path = "auth/userpass/users/${var.username}"

  data_json = jsonencode({
    password = var.user-password
    policies = "default,duo-mfa-policy"
  })

  depends_on = [vault_auth_backend.userpass, vault_policy.duo_mfa_policy]
}

# Create userpass user - this does not exist in Duo
resource "vault_generic_secret" "user-not-exists" {
  path = "auth/userpass/users/${var.username-not-exists}"

  data_json = jsonencode({
    password = var.user-password
    policies = "default,duo-mfa-policy"
  })

  depends_on = [vault_auth_backend.userpass, vault_policy.duo_mfa_policy]
}

# Create identity entity
resource "vault_identity_entity" "user_entity" {
  name     = var.username
  policies = ["default", "duo-mfa-policy"]

  depends_on = [vault_policy.duo_mfa_policy]
}

# Create entity alias (links entity to userpass auth)
# It's how Vault knows "this login from userpass is actually ajaypatel entity.
resource "vault_identity_entity_alias" "user_alias" {
  name           = var.username
  mount_accessor = vault_auth_backend.userpass.accessor
  canonical_id   = vault_identity_entity.user_entity.id
}

# Create DUO MFA method - essentially connecting Vault to the DUO Instance 
resource "vault_identity_mfa_duo" "duo_mfa" {
  integration_key = var.duo-integration-key
  secret_key      = var.duo-secret-key
  api_hostname    = var.duo-api-hostname

  # Dynamic username format using the userpass accessor
  username_format = "{{identity.entity.aliases.${vault_auth_backend.userpass.accessor}.name}}"

  depends_on = [vault_identity_entity_alias.user_alias]
}

# Enforce MFA on the Auth Method userpass (done via the auth_method _accessor)
resource "vault_identity_mfa_login_enforcement" "duo_enforcement" {
  name                  = "duo_enforcement"
  mfa_method_ids        = [vault_identity_mfa_duo.duo_mfa.method_id]
  auth_method_accessors = [vault_auth_backend.userpass.accessor]
  auth_method_types     = concat(vault_auth_backend.userpass.type)
}

