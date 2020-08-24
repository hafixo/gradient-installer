locals {
  ssh_key_path = "${path.module}/ssh_key"
}

resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
}

provider "paperspace" {
  region  = var.region
  api_key = var.admin_user_api_key
}

data "paperspace_user" "admin" {
  email   = var.admin_email
  team_id = var.team_id

}

resource "paperspace_script" "add_public_ssh_key" {
  name        = "Add public SSH key"
  description = "Add public SSH key on machine create"
  script_text = <<EOF
        #!/bin/bash
        echo "${tls_private_key.ssh_key.public_key_openssh}" >> /home/paperspace/.ssh/authorized_keys
    EOF
  is_enabled  = true
  run_once    = true

  provisioner "local-exec" {
    command = <<EOF
            sleep 20
        EOF
  }
}

resource "paperspace_network" "network" {
  team_id = var.team_id
}

resource "paperspace_machine" "main" {
  depends_on = [
    paperspace_script.add_public_ssh_key,
    tls_private_key.ssh_key,
  ]

  region           = var.region
  name             = "${var.cluster_id}-${var.name}-main"
  machine_type     = var.master.machine_type
  size             = var.master.machine_storage
  billing_type     = "hourly"
  assign_public_ip = true
  template_id      = var.master.template_id
  user_id          = data.paperspace_user.admin.id
  team_id          = data.paperspace_user.admin.team_id
  script_id        = paperspace_script.add_public_ssh_key.id
  network_id       = paperspace_network.network.handle
  live_forever     = true
  is_managed       = var.is_managed

  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      user        = "paperspace"
      host        = self.public_ip_address
      private_key = tls_private_key.ssh_key.private_key_pem
    }
  }

  provisioner "local-exec" {
    command = <<EOF
            echo "${tls_private_key.ssh_key.private_key_pem}" > ${local.ssh_key_path} && chmod 600 ${local.ssh_key_path} && \
            ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook \
            --key-file ${local.ssh_key_path} \
            -i '${paperspace_machine.main.public_ip_address},' \
            -e "install_nfs_server=true" \
            -e "nfs_subnet_host_with_netmask=${paperspace_network.network.network}/${paperspace_network.network.netmask}" \
            ${path.module}/ansible/playbook-gradient-metal-ps-cloud-node.yaml
        EOF
  }
}

resource "paperspace_script" "autoscale" {
  name        = "Autoscale cluster"
  description = "Autoscales cluster"
  script_text = <<EOF
        #!/usr/bin/env bash

        sudo su -

        until docker ps -a || (( count++ >= 30 )); do echo "Check if docker is up..."; sleep 2; done

        sudo chmod 777 /var/run/docker.sock

        echo "${tls_private_key.ssh_key.public_key_openssh}" >> /home/paperspace/.ssh/authorized_keys
        export MACHINE_ID=`curl https://metadata.paperspace.com/meta-data/machine | grep hostname | sed 's/^.*: "\(.*\)".*/\1/'`
        curl -H 'Content-Type:application/json' -H 'X-API-Key: ${var.cluster_api_key}' -XPOST '${var.api_host}/clusterMachines/register' -d '{"clusterId":"${var.cluster_id}", "machineId":"$MACHINE_ID"}'

        curl -H 'Content-Type:application/json' -H 'X-API-Key: ${var.cluster_api_key}' -XPOST '${var.api_host}/clusters/updateCluster' -d '{"id":"${var.cluster_id}", "scale": true }'
    EOF
  is_enabled  = true
  run_once    = true
}

resource "paperspace_autoscaling_group" "main" {
  for_each = var.autoscaling_groups

  name              = "${var.cluster_id}-${each.value.machine_type}"
  cluster_id        = var.cluster_id
  machine_type      = each.value.machine_type
  template_id       = each.value.template_id
  max               = each.value.max
  min               = each.value.min
  network_id        = paperspace_network.network.handle
  startup_script_id = paperspace_script.autoscale.id
}

// Kubernetes
module "kubernetes" {
  source = "../modules/kubernetes"
  # TODO make this work
  enable = ! local.has_k8s

  name = var.name

  authentication_sans = var.k8s_sans
  k8s_version         = local.k8s_version
  kubeconfig_path     = var.kubeconfig_path
  kubelet_extra_binds = []
  master_node         = var.k8s_master_node
  reboot_gpu_nodes    = var.reboot_gpu_nodes
  service_pool_name   = local.service_pool_name
  setup_docker        = var.setup_docker
  setup_nvidia        = var.setup_nvidia
  ssh_key_private     = var.ssh_key == "" ? file(pathexpand(var.ssh_key_path)) : var.ssh_key
  ssh_user            = var.ssh_user
  write_kubeconfig    = var.write_kubeconfig
  workers             = var.k8s_workers
}

resource "null_resource" "register_managed_cluster_network" {
  provisioner "local-exec" {
    command = <<EOF
            if [ ${var.is_managed} == true ] ; then
                curl -H 'Content-Type:application/json' -H 'X-API-Key: ${var.cluster_api_key}' -XPOST '${var.api_host}/clusters/updateCluster' -d '{"id":"${var.cluster_id}", "attributes":{"networkId":"${paperspace_network.network.id}"}}'
            fi
        EOF
  }
}

resource "null_resource" "register_managed_cluster_machine_main" {
  provisioner "local-exec" {
    command = <<EOF
            if [ ${var.is_managed} == true ] ; then
                curl -H 'Content-Type:application/json' -H 'X-API-Key: ${var.cluster_api_key}' -XPOST '${var.api_host}/clusterMachines/register' -d '{"clusterId":"${var.cluster_id}", "machineId":"${paperspace_machine.gradient_main.id}"}'
            fi
        EOF
  }
}

provider "cloudflare" {
  version = "~> 2.0"
  email   = var.cloudflare.email
  api_key = var.cloudflare.api_key
}

resource "cloudflare_record" "subdomain" {
  count   = var.cloudflare.api_key == "" && var.cloudflare.email == "" && var.cloudflare.zone_id == "" ? 0 : 1
  zone_id = var.cloudflare.zone_id
  name    = var.cloudflare.domain
  value   = paperspace_machine.main.public_ip_address
  type    = "A"
  ttl     = 3600
  proxied = var.cloudflare.is_proxied
}

resource "cloudflare_record" "subdomain_wildcard" {
  count   = var.cloudflare.api_key == "" && var.cloudflare.email == "" && var.cloudflare.zone_id == "" ? 0 : 1
  zone_id = var.cloudflare.zone_id
  name    = "*.${var.cloudflare.domain}"
  value   = paperspace_machine.main.public_ip_address
  type    = "A"
  ttl     = 3600
  proxied = var.cloudflare.s_proxied
}

output "main_node_public_ip_address" {
  value = paperspace_machine.main.public_ip_address
}

output "network_handle" {
  value = paperspace_network.network.handle
}
