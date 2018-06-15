variable "token" {}
variable "master_hosts" {
  default = 1
}

variable "docker_opts" {
  type = "list"
  default = ["--iptables=false", "--ip-masq=false"]
}

provider "hcloud" {
  token = "${var.token}"
}

module "provider_master" {
  source = "git::https://github.com/suquant/tf_hcloud.git?ref=v1.0.0"

  count = "${var.master_hosts}"
  token = "${var.token}"

  name        = "master"
  server_type = "cx21"
}

module "wireguard" {
  source = "git::https://github.com/suquant/tf_wireguard.git?ref=v1.0.0"

  count         = "${var.master_hosts}"
  connections   = ["${module.provider_master.public_ips}"]
  private_ips   = ["${module.provider_master.private_ips}"]
}


module "etcd" {
  source = "git::https://github.com/suquant/tf_etcd.git?ref=v1.0.0"

  count       = "${var.master_hosts}"
  connections = "${module.provider_master.public_ips}"

  hostnames   = "${module.provider_master.hostnames}"
  private_ips = ["${module.wireguard.ips}"]
}

module "docker_master" {
  source = "git::https://github.com/suquant/tf_docker.git?ref=v1.0.0"

  count       = "${var.master_hosts}"
  # Fix of conccurent apt install running: will run only after wireguard has been installed
  connections = ["${module.wireguard.public_ips}"]

  docker_opts = ["${var.docker_opts}"]
}

module "kuber_master" {
  source = "git::https://github.com/suquant/tf_kuber_master.git?ref=v1.0.0"

  count           = "${var.master_hosts}"
  connections     = ["${module.docker_master.public_ips}"]

  private_ips     = ["${module.provider_master.private_ips}"]
  etcd_endpoints  = "${module.etcd.client_endpoints}"
}

variable "worker_hosts" {
  default = 3
}

module "provider_worker" {
  source = "git::https://github.com/suquant/tf_hcloud.git?ref=v1.0.0"

  count = "${var.worker_hosts}"
  token = "${var.token}"

  name        = "worker"
  ssh_names   = ["${module.provider_master.ssh_names}"]
  ssh_keys    = []
  server_type = "cx11"
}

module "docker_worker" {
  source = "git::https://github.com/suquant/tf_docker.git?ref=v1.0.0"

  count       = "${var.worker_hosts}"
  connections = ["${module.provider_worker.public_ips}"]

  docker_opts = ["${var.docker_opts}"]
}

module "kuber_worker" {
  source = ".."

  count       = "${var.worker_hosts}"
  connections = ["${module.docker_worker.public_ips}"]

  join_command        = "${module.kuber_master.join_command}"
  kubernetes_version  = "${module.kuber_master.kubernetes_version}"
}