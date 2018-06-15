variable "count" {}

variable "connections" {
  type = "list"
}

variable "kubernetes_version" {
  default = "1.10"
}

variable "join_command" {}
