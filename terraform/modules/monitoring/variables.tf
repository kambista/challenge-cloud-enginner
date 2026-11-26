variable "project_id" {
  type = string
}

variable "name" {
  type = string
}

variable "namespace" {
  type = string
}

variable "host" {
  type = string
}

variable "alert_email" {
  type = string
}

variable "error_rate_threshold" {
  type    = number
  default = 0.05
}

variable "restart_threshold" {
  type    = number
  default = 3
}
