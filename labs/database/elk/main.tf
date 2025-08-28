# Mount the database secrets engine if not already mounted
resource "vault_mount" "database" {
  path        = "database/elk/${var.application-name}"
  type        = "database"
  description = "Database secrets engine for ELK credential mangement"
}

# Configure the ELK database connection using plugin
# Note that the username and password below must exist before this will successfully
resource "vault_database_secret_backend_connection" "elk" {
  backend     = vault_mount.database.path
  name        = var.database-name
  plugin_name = "elasticsearch-database-plugin"
  allowed_roles = concat([
    local.dynamic-admin-role-name,
    local.dynamic-readonly-role-name,
    "vault-static-user-*-role" # this is importatant. the star ensures that future static roles can be added - providing they can follow the confention - 
  ])

  // rotation_period = 20 # Rotate the credential after this period in seconds - for dev & testing leave this out

  elasticsearch {
    url      = "https://elasticsearch:9200"
    username = "elastic"
    password = "password123"
    ca_cert  = "/vault/ca.crt"
    insecure = false
  }

  depends_on = [vault_mount.database]

}

module "dynamic_roles" {
  source             = "./modules/roles/dynamic/"
  readonly-role-name = local.dynamic-readonly-role-name
  admin-role-name    = local.dynamic-admin-role-name
  db-name            = vault_database_secret_backend_connection.elk.name
  mount-path         = vault_mount.database.path

  depends_on = [vault_database_secret_backend_connection.elk]
}

module "static_roles" {
  source             = "./modules/roles/static/"
  existing-elk-users = local.existing-elk-users
  db-name            = vault_database_secret_backend_connection.elk.name
  mount-path         = vault_mount.database.path

  depends_on = [vault_database_secret_backend_connection.elk]
}
