# Define the Redis role
resource "vault_database_secret_backend_role" "redis_readonly_role" {
  backend = var.mount-path
  name    = var.readonly-role-name
  db_name = var.db-name

  # Read-only ACL permissions for dynamic users
  creation_statements = [
    "[\"~*\", \"+@read\", \"+info\"]"
  ]

  // Empty renew_statements makes credentials non-renewable
  // renew_statements = []

  // IN SECONDS
  default_ttl = 7200 # 2 hours
  max_ttl     = 86400 # 1 Day
}

// Create Redis role
resource "vault_database_secret_backend_role" "redis_admin_role" {
  backend = var.mount-path
  name    = var.admin-role-name
  db_name = var.db-name

  // Admin ACL permissions for dynamic users (full access)
  creation_statements = [
    "[\"~*\", \"+@all\"]"
  ]

  // Empty renew_statements makes credentials non-renewable
  // renew_statements = []

  // IN SECONDS
  default_ttl = 300  # 5 minutes
  max_ttl     = 7200 # 2 hours
}
