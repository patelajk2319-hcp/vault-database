variable "duo-integration-key" {
  description = "DUO Integration Key"
  type        = string
  sensitive   = true
}

variable "duo-secret-key" {
  description = "DUO Integration Key"
  type        = string
  sensitive   = true
}

variable "duo-api-hostname" {
  description = "DUO Integration Key"
  type        = string
  sensitive   = true
}

variable "username" {
  description = "Username for authentication exists in Duo"
  type        = string
}

variable "user-password" {
  description = "Password for the user"
  type        = string
  sensitive   = true
}

variable "username-not-exists" {
  description = "Username for authentication but does not exist in Duo"
  type        = string
}