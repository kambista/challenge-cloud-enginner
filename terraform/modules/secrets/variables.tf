variable "project_id" {
  type = string
}

variable "mongo_host" {
  type = string
}

variable "database" {
  type    = string
  default = "quotes"
}

variable "app_username" {
  type    = string
  default = "quotes-api"
}

variable "accessors" {
  type    = list(string)
  default = []
}

variable "labels" {
  type    = map(string)
  default = {}
}
