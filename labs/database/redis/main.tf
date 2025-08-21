# Mount the database secrets engine if not already mounted
resource "vault_mount" "database" {
  path        = "database/redis/${var.application-name}"
  type        = "database"
  description = "Database secrets engine for Redis credential mangement"
}

# Configure the Redis database connection using a custom plugin
# Note that the username and password below must exist before this will successfully
resource "vault_database_secret_backend_connection" "redis" {
  backend     = vault_mount.database.path
  name        = var.database-name
  plugin_name = "redis-database-plugin"
  allowed_roles = concat([
    local.dynamic-admin-role-name,
    local.dynamic-readonly-role-name,
    "vault-static-user-*-role" # this is importatant. the star ensures that future static roles can be added - providing they can follow the confention - 
  ])

  rotation_period = 20 # Rotate the credential after this period in seconds - for dev & testing leave this out
  
  redis {
    host     = "redis"
    port     = 6379
    username = "vault-root-user"
    password = "SuperSecretPass123"
    tls      = false
  }

  depends_on = [vault_mount.database]

}

module "dynamic_roles" {
  source             = "./modules/roles/dynamic/"
  readonly-role-name = local.dynamic-readonly-role-name
  admin-role-name    = local.dynamic-admin-role-name
  db-name            = vault_database_secret_backend_connection.redis.name
  mount-path         = vault_mount.database.path

  depends_on = [vault_database_secret_backend_connection.redis]
}

module "static_roles" {
  source               = "./modules/roles/static/"
  existing-redis-users = local.existing-redis-users
  db-name              = vault_database_secret_backend_connection.redis.name
  mount-path           = vault_mount.database.path

  depends_on = [vault_database_secret_backend_connection.redis]
}
