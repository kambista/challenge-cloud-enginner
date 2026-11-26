variable "project_id" {
  type = string
}

variable "name" {
  type = string
}

variable "enable_security_policy" {
  type    = bool
  default = true
}

variable "allowed_countries" {
  description = "Códigos ISO 3166-1 alpha-2. Vacío desactiva el geobloqueo."
  type        = list(string)
  default     = []
}

variable "rate_limit_per_minute" {
  type    = number
  default = 300
}
