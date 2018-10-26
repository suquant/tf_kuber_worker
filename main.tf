variable "count" {}

variable "connections" {
  type = "list"
}

variable "private_ips" {
  type = "list"
}

variable "kubernetes_version" {
  default = "1.12.1"
}

variable "kubernetes_cni_version" {
  default = "0.6.0-00"
}

variable "node_labels" {
  type = "list"
  default = []
}

variable "node_taints" {
  type = "list"
  default = []
}

variable "join_command" {}


resource "null_resource" "kubernetes" {
  count = "${var.count}"

  connection {
    host  = "${element(var.connections, count.index)}"
    user  = "root"
    agent = true
  }

  provisioner "file" {
    content     = "${data.template_file.apt_preference.rendered}"
    destination = "/etc/apt/preferences.d/kubernetes"
  }

  provisioner "remote-exec" {
    inline = [
      "echo 'net.ipv4.ip_forward=1' > /etc/sysctl.d/ipv4_forward.conf",
      "echo 'net.bridge.bridge-nf-call-iptables=1' > /etc/sysctl.d/bridge_nf_call_iptables.conf",
      "sysctl -p",
      "curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -",
      "echo \"deb [arch=amd64] https://apt.kubernetes.io/ kubernetes-$$(lsb_release -cs) main\" > /etc/apt/sources.list.d/kubernetes.list",

      "apt update",
      "DEBIAN_FRONTEND=noninteractive apt install -yq kubelet kubeadm kubectl kubernetes-cni ipvsadm jq",
    ]
  }

  provisioner "file" {
    content     = "${element(data.template_file.configuration.*.rendered, count.index)}"
    destination = "/etc/kubernetes/configuration.yml"
  }

  provisioner "remote-exec" {
    inline = [
      "kubeadm reset --force",
      "kubeadm join --config /etc/kubernetes/configuration.yml",
      "iptables -t nat -F",
    ]
  }
}

data "template_file" "apt_preference" {
  template = "${file("${path.module}/templates/apt-preference.conf")}"

  vars {
    kubernetes_version      = "${var.kubernetes_version}"
    kubernetes_cni_version  = "${var.kubernetes_cni_version}"
  }
}

data "null_data_source" "join" {
  inputs {
    discovery_server             = "${element(split(" ", var.join_command), 2)}"
    discovery_token              = "${element(split(" ", var.join_command), 4)}"
    discovery_token_ca_cert_hash = "${element(split(" ", var.join_command), 6)}"
  }
}

data "template_file" "configuration" {
  count = "${var.count}"

  template = "${file("${path.module}/templates/configuration.yml")}"

  vars {
    count                        = "${var.count}"
    kubernetes_version           = "${var.kubernetes_version}"
    discovery_server             = "${data.null_data_source.join.outputs["discovery_server"]}"
    discovery_token              = "${data.null_data_source.join.outputs["discovery_token"]}"
    discovery_token_ca_cert_hash = "${data.null_data_source.join.outputs["discovery_token_ca_cert_hash"]}"
    node_ip                      = "${element(var.private_ips, count.index)}"
    node_labels                  = "${join(",", var.node_labels)}"
    node_taints                  = "${join(",", var.node_taints)}"
  }
}


output "public_ips" {
  value = ["${var.connections}"]

  depends_on  = ["null_resource.kubernetes"]
}

output "private_ips" {
  value = ["${var.private_ips}"]

  depends_on  = ["null_resource.kubernetes"]
}