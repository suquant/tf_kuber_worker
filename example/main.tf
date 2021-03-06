variable "token" {}
variable "master_hosts" {
  default = 1
}
variable "worker_hosts" {
  default = 2
}

variable "docker_opts" {
  type = "list"
  default = [
    "--iptables=false",
    "--ip-masq=false",
    "--storage-driver=overlay2",
    "--live-restore",
    "--log-level=warn",
    "--bip=169.254.123.1/24",
    "--log-driver=json-file",
    "--log-opt=max-size=10m",
    "--log-opt=max-file=5",
    "--insecure-registry 10.0.0.0/8"
  ]
}

provider "hcloud" {
  token = "${var.token}"
}

module "provider_master" {
  source = "git::https://github.com/suquant/tf_hcloud.git"

  count = "${var.master_hosts}"

  name        = "master"
  server_type = "cx11"
}

module "provider_worker" {
  source = "git::https://github.com/suquant/tf_hcloud.git"

  count = "${var.worker_hosts}"

  name               = "worker"
  ssh_names          = ["${module.provider_master.ssh_names}"]
  ssh_keys           = []
  server_type        = "cx11"
}

module "wireguard" {
  source = "git::https://github.com/suquant/tf_wireguard.git"

  count         = "${var.master_hosts + var.worker_hosts}"
  connections   = ["${concat(module.provider_master.public_ips, module.provider_worker.public_ips)}"]
  private_ips   = ["${concat(module.provider_master.private_ips, module.provider_worker.private_ips)}"]
  overlay_cidr  = "10.254.254.254/32"
}


module "etcd" {
  source = "git::https://github.com/suquant/tf_etcd.git"

  count       = "${var.master_hosts}"
  connections = "${slice(module.wireguard.public_ips, 0, var.master_hosts)}"

  hostnames   = ["${slice(module.provider_master.hostnames, 0, var.master_hosts)}"]
  private_ips = ["${slice(module.wireguard.vpn_ips, 0, var.master_hosts)}"]
}

module "docker" {
  source = "git::https://github.com/suquant/tf_docker.git"

  count       = "${var.master_hosts + var.worker_hosts}"
  connections = ["${module.wireguard.public_ips}"]

  docker_opts = ["${var.docker_opts}"]
}

module "kuber_master" {
  source = "git::https://github.com/suquant/tf_kuber_master.git"

  count           = "${var.master_hosts}"
  connections     = ["${slice(module.docker.public_ips, 0, var.master_hosts)}"]

  private_ips     = ["${slice(module.wireguard.vpn_ips, 0, var.master_hosts)}"]
  etcd_endpoints  = "${module.etcd.client_endpoints}"
}

module "kuber_worker" {
  source = ".."

  count       = "${var.worker_hosts}"
  connections = ["${slice(module.docker.public_ips, var.master_hosts, var.master_hosts + var.worker_hosts)}"]

  private_ips         = ["${slice(module.wireguard.vpn_ips, var.master_hosts, var.master_hosts + var.worker_hosts)}"]
  join_command        = "${module.kuber_master.join_command}"
  kubernetes_version  = "${module.kuber_master.kubernetes_version}"
}