variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "bucket_name" {
  type = string
}

variable "retention_days" {
  type    = number
  default = 7
}

variable "force_destroy" {
  type    = bool
  default = true
}

variable "writers" {
  type    = list(string)
  default = []
}

variable "readers" {
  type    = list(string)
  default = []
}

variable "labels" {
  type    = map(string)
  default = {}
}
