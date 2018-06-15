output "public_ips" {
  value = ["${var.connections}"]

  depends_on  = ["null_resource.join"]
}

output "kubernetes_version" {
  value = "${var.kubernetes_version}"
}