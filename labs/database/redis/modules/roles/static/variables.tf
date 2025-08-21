
variable "db-name" {
  type        = string
  description = "The name of the database name"
}

variable "mount-path" {
  type        = string
  description = "The name of the path where the secrets engine is mounted name"
}

variable "existing-redis-users" {
  description = "List of existing Redis users to manage"
  type = list(object({
    username        = string
    rotation_period = string
    description     = optional(string, "")
  }))
}