terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
  required_version = ">= 0.13"
}

provider "yandex" {
  service_account_key_file = "./tf_key.json"
  folder_id                = local.folder_id
  zone                     = "ru-central1-a"
}

resource "yandex_vpc_network" "ynet" {}

resource "yandex_vpc_subnet" "ysubnet" {
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.ynet.id
  v4_cidr_blocks = ["10.5.0.0/24"]
}

resource "yandex_container_registry" "registry1" {
  name = "registry1"
}

locals {
  folder_id = "b1g3f87cb3s6b33dg6jl"
  service-accounts = toset([
    "hewki-sa-2",
  ])
  catgpt-sa-roles = toset([
    "container-registry.images.puller",
    "monitoring.editor",
  ])
}
resource "yandex_iam_service_account" "service-accounts" {
  for_each = local.service-accounts
  name     = each.key
}
resource "yandex_resourcemanager_folder_iam_member" "catgpt-roles" {
  for_each  = local.catgpt-sa-roles
  folder_id = local.folder_id
  member    = "serviceAccount:${yandex_iam_service_account.service-accounts["hewki-sa-2"].id}"
  role      = each.key
}

data "yandex_compute_image" "coi" {
  family = "container-optimized-image"
}
resource "yandex_compute_instance" "catgpt-1" {
  platform_id        = "standard-v2"
  service_account_id = yandex_iam_service_account.service-accounts["hewki-sa-2"].id
  resources {
    cores         = 2
    memory        = 1
    core_fraction = 5
  }
  scheduling_policy {
    preemptible = true
  }
  network_interface {
    subnet_id = yandex_vpc_subnet.ysubnet.id
    nat       = true
  }
  boot_disk {
    initialize_params {
      type     = "network-hdd"
      size     = "30"
      image_id = data.yandex_compute_image.coi.id
    }
  }
  metadata = {
	serial-port-enable = 1
	user-data = "#cloud-config\nruncmd:\n  - wget -O - https://monitoring.api.cloud.yandex.net/monitoring/v2/unifiedAgent/config/install.sh | bash"
    docker-compose = file("${path.module}/docker-compose.yaml")
#    ssh-keys       = "ubuntu:${file("~/.ssh/devops_training.pub")}"
    ssh-keys = file("${path.module}/meta.txt")
  }
}

resource "yandex_compute_instance" "catgpt-2" {
  platform_id        = "standard-v2"
  service_account_id = yandex_iam_service_account.service-accounts["hewki-sa-2"].id
  resources {
    cores         = 2
    memory        = 1
    core_fraction = 5
  }
  scheduling_policy {
    preemptible = true
  }
  network_interface {
    subnet_id = yandex_vpc_subnet.ysubnet.id
    nat       = true
  }
  boot_disk {
    initialize_params {
      type     = "network-hdd"
      size     = "30"
      image_id = data.yandex_compute_image.coi.id
    }
  }
  metadata = {
	serial-port-enable = 1
	user-data = "#cloud-config\nruncmd:\n  - wget -O - https://monitoring.api.cloud.yandex.net/monitoring/v2/unifiedAgent/config/install.sh | bash"
    docker-compose = file("${path.module}/docker-compose.yaml")
    ssh-keys       = "ubuntu:${file("~/.ssh/devops_training.pub")}"
  }
}

resource "yandex_lb_target_group" "lb_group" {
  name      = "my-target-group"
#  region_id = "${yandex_vpc_subnet.ysubnet.zone}"

  target {
    subnet_id = "${yandex_vpc_subnet.ysubnet.id}"
    address   = "${yandex_compute_instance.catgpt-1.network_interface.0.ip_address}"
  }

  target {
    subnet_id = "${yandex_vpc_subnet.ysubnet.id}"
    address   = "${yandex_compute_instance.catgpt-2.network_interface.0.ip_address}"
  }
}

resource "yandex_lb_network_load_balancer" "ylb" {
  name = "ylb"

  listener {
    name = "my-listener"
    port = 8080
    external_address_spec {
      ip_version = "ipv4"
    }
  }

  listener {
    name = "metrics"
    port = 9090
    external_address_spec {
      ip_version = "ipv4"
    }
  }

  attached_target_group {
    target_group_id = "${yandex_lb_target_group.lb_group.id}"

    healthcheck {
      name = "http"
      http_options {
        port = 8080
        path = "/ping"
      }
    }
  }
}