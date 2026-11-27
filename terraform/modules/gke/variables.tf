variable "project_id" {
  type = string
}

variable "zone" {
  type = string
}

variable "cluster_name" {
  type    = string
  default = "kambista-gke-cluster"
}

variable "vpc_name" {
  type = string
}

variable "subnet_name" {
  type = string
}

variable "node_service_account" {
  type = string
}

variable "node_count" {
  type    = number
  default = 2
}

variable "machine_type" {
  type    = string
  default = "e2-medium"
}