resource "vault_database_secret_backend_role" "elk_readwrite_role" {
  backend = var.mount-path
  name    = var.readonly-role-name
  db_name = var.db-name

  # Read & write for this role to create dynamic users
  creation_statements = [
    jsonencode({
      elasticsearch_role_definition = {
        indices = [
          {
            names      = ["*"]
            privileges = ["read", "write", "create", "delete", "index"]
          }
        ]
      }
    })
  ]

  // Empty renew_statements makes credentials non-renewable
  // renew_statements = []

  // IN SECONDS
  default_ttl = 7200  # 2 hours
  max_ttl     = 86400 # 1 Day
}


resource "vault_database_secret_backend_role" "elk_admin_role" {
  backend = var.mount-path
  name    = var.admin-role-name
  db_name = var.db-name

  # Admin for this role to create dynamic users
  creation_statements = [
    jsonencode({
      elasticsearch_role_definition = {
        cluster = ["all"]
        indices = [
          {
            names      = ["*"]
            privileges = ["all"]
          }
        ]
      }
    })
  ]

  // Empty renew_statements makes credentials non-renewable
  // renew_statements = []

  // IN SECONDS
  default_ttl = 7200  # 2 hours
  max_ttl     = 86400 # 1 Day
}