resource "vault_database_secret_backend_static_role" "elk_static_users" {
  for_each = { for user in var.existing-elk-users : user.username => user }

  backend         = var.mount-path
  name            = "${each.value.username}-role"
  db_name         = var.db-name
  username        = each.value.username
  rotation_period = each.value.rotation_period
}

resource "vault_policy" "elk-reader" {
  for_each = { for user in var.existing-elk-users : user.username => user }

  name   = "elk-${each.value.username}-reader-policy"
  policy = data.vault_policy_document.read[each.key].hcl
}

resource "vault_policy" "elk-list" {
  for_each = { for user in var.existing-elk-users : user.username => user }

  name   = "elk-list-policy"
  policy = data.vault_policy_document.list.hcl
}

# Create separate policy documents for each user's read access
data "vault_policy_document" "read" {
  for_each = { for user in var.existing-elk-users : user.username => user }

  rule {
    path         = "database/elk/my-elk-application/static-creds/${each.value.username}-role"
    capabilities = ["read"]
    description  = "Allows for Reading Secrets"
  }
}

# Single policy document for list access
data "vault_policy_document" "list" {
  rule {
    path         = "database/elk/my-elk-application/static-creds"
    capabilities = ["list"]
    description  = "Allows for listing secrets"
  }
}