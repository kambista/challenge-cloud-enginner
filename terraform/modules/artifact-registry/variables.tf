variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "name" {
  type = string
}

variable "keep_count" {
  type    = number
  default = 10
}

variable "readers" {
  type    = list(string)
  default = []
}

variable "writers" {
  type    = list(string)
  default = []
}

variable "labels" {
  type    = map(string)
  default = {}
}
