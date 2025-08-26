variable "readonly-role-name" {
  type        = string
  description = "The name of the readonly role"
}

variable "admin-role-name" {
  type        = string
  description = "The name of the admin role"
}

variable "db-name" {
  type        = string
  description = "The name of the database name"
}

variable "mount-path" {
  type        = string
  description = "The name of the path where the secrets engine is mounted name"
}