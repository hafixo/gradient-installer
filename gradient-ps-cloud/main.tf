terraform {
    required_providers {
        cloudflare = {
            source  = "cloudflare/cloudflare"
            version = "~> 2.10.0"
        }
        rancher2 = {
            source = "rancher/rancher2"
            version = "1.10.1"
        }
    }
}

locals {
    asg_types = {
        "C5"={
            type = "cpu"
        },
        "C7"={
            type = "cpu"
        },
        "C10"={
            type = "cpu"
        },
        "P4000"={
            type = "gpu"
        },
        "P5000"={
            type = "gpu"
        },
        "V100"={
            type = "gpu"
        },
    }
    asg_max_sizes = merge({
        "C5"=10,
        "C7"=10,
        "C10"=10,
        "P4000"=10,
        "P5000"=10,
        "V100"=10,
    }, var.asg_min_sizes)

    asg_min_sizes = merge({
        "C5"=10,
        "C7"=10,
        "C10"=10,
        "P4000"=10,
        "P5000"=10,
        "V100"=10,
    }, var.asg_min_sizes)

    cluster_autoscaler_cloudprovider = "paperspace"
    cluster_autoscaler_enabled = true

    ssh_key_path = "${path.module}/ssh_key"
}

provider "cloudflare" {
    version = "~> 2.0"
    email   = var.cloudflare_email
    api_key = var.cloudflare_api_key
}

provider "paperspace" {
    region = var.region
    api_key = var.admin_user_api_key
}

data "paperspace_user" "admin" {
    email = var.admin_email
    team_id = var.team_id
}

resource "tls_private_key" "ssh_key" {
    algorithm = "RSA"
}

resource "paperspace_script" "add_public_ssh_key" {
    name = "Add public SSH key"
    description = "Add public SSH key on machine create"
    script_text = <<EOF
        #!/bin/bash
        echo "${tls_private_key.ssh_key.public_key_openssh}" >> /home/paperspace/.ssh/authorized_keys
    EOF
    is_enabled = true
    run_once = true

    provisioner "local-exec" {
        command = <<EOF
            sleep 20
        EOF
    }
}

resource "paperspace_network" "network" {
    team_id = var.team_id_integer
}

resource "paperspace_machine" "gradient_main" {
    depends_on = [
        paperspace_script.add_public_ssh_key,
        tls_private_key.ssh_key,
    ]

    region = var.region
    name = "${var.cluster_handle}-${var.name}-main"
    machine_type = var.machine_type_main
    size = var.machine_storage_main
    billing_type = "hourly"
    assign_public_ip = true
    template_id = var.machine_template_id_main
    user_id = data.paperspace_user.admin.id
    team_id = data.paperspace_user.admin.team_id
    script_id = paperspace_script.add_public_ssh_key.id
    network_id = paperspace_network.network.handle
    live_forever = true
    is_managed = true

    provisioner "remote-exec" {
        connection {
            type     = "ssh"
            user     = "paperspace"
            host     = self.public_ip_address
            private_key = tls_private_key.ssh_key.private_key_pem
        }
    } 

    provisioner "local-exec" {
        command = <<EOF
            echo "${tls_private_key.ssh_key.private_key_pem}" > ${local.ssh_key_path} && chmod 600 ${local.ssh_key_path} && \
            ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook \
            --key-file ${local.ssh_key_path} \
            -i '${paperspace_machine.gradient_main.public_ip_address},' \
            -e "install_nfs_server=true" \
            -e "nfs_subnet_host_with_netmask=${paperspace_network.network.network}/${paperspace_network.network.netmask}" \
            ${path.module}/ansible/playbook-gradient-metal-ps-cloud-node.yaml
        EOF
    }
}
/*
module "gradient_metal" {
    source = "../gradient-metal"

    name = var.name

    amqp_hostname = var.amqp_hostname

    artifacts_access_key_id = var.artifacts_access_key_id
    artifacts_path = var.artifacts_path
    artifacts_secret_access_key = var.artifacts_secret_access_key
    sentry_dsn = var.sentry_dsn

    cluster_autoscaler_autoscaling_groups = [for autoscaling_group in local.autoscaling_groups: {
        min: autoscaling_group.min
        max: autoscaling_group.max
        name: autoscaling_group.id
    }]
    cluster_autoscaler_cloudprovider = local.cluster_autoscaler_cloudprovider
    cluster_autoscaler_enabled = local.cluster_autoscaler_enabled
    cluster_handle = var.cluster_handle
    cluster_apikey = var.cluster_apikey

    domain = var.domain
    gradient_processing_version = var.gradient_processing_version

    elastic_search_host = var.elastic_search_host
    elastic_search_index = var.name
    elastic_search_password = var.elastic_search_password
    elastic_search_user = var.elastic_search_user

    helm_repo_password = var.helm_repo_password
    helm_repo_username = var.helm_repo_username
    helm_repo_url = var.helm_repo_url
    kubeconfig_path = var.kubeconfig_path

    logs_host = var.logs_host
    letsencrypt_dns_name = var.letsencrypt_dns_name
    letsencrypt_dns_settings = var.letsencrypt_dns_settings
    traefik_prometheus_auth = var.traefik_prometheus_auth

    k8s_master_node = {
        ip = paperspace_machine.gradient_main.public_ip_address
        internal-address = paperspace_machine.gradient_main.private_ip_address
        pool-type = "cpu"
        pool-name = "metal-cpu"
    }
    k8s_workers = concat(
        [
            for cpu_worker in paperspace_machine.gradient_workers_cpu : {
                ip = cpu_worker.public_ip_address
                internal-address = cpu_worker.private_ip_address
                pool-type = "cpu"
                pool-name = "metal-cpu"
            }
        ],
        [
            for gpu_worker in paperspace_machine.gradient_workers_gpu : {
                ip = gpu_worker.public_ip_address
                internal-address = gpu_worker.private_ip_address
                pool-type = "gpu"
                pool-name = "metal-gpu"
            }
        ],
        [ for worker in var.workers : {
            ip = worker["ip"]
            internal-address = worker["internal-address"]
            pool-type = worker["machine_type"] == var.machine_type_worker_gpu ? "gpu" : "cpu"
            pool-name = worker["machine_type"] == var.machine_type_worker_gpu ? "metal-gpu" : "metal-cpu"
        }]
    )

    shared_storage_path = "/srv/gradient"
    shared_storage_server = paperspace_machine.gradient_main.private_ip_address
    ssh_key = tls_private_key.ssh_key.private_key_pem
    ssh_user = "paperspace"
}
*/

resource "rancher2_cluster" "main" {
  name = var.name
  description = var.name
  rke_config {
      nodes {
            address = paperspace_machine.gradient_main.public_ip_address
            internal_address = paperspace_machine.gradient_main.private_ip_address
            labels = {
                "node-role.kubernetes.io/master" = ""
                "node-role.kubernetes.io/controller" = true
                "paperspace.com/pool-name" = "services-small"
                "paperspace.com/pool-type" = "cpu"
            }
            role = [
                "controlplane",
                "etcd",
                "worker",
            ]

/*
            "node-role.kubernetes.io/master" = ""
            "node-role.kubernetes.io/controller" = true
            "paperspace.com/pool-name" = var.service_pool_name
            "paperspace.com/pool-type" = var.master_node["pool-type"]
*/

            ssh_key = tls_private_key.ssh_key.private_key_pem
            user    = "paperspace"
      }
        ingress {
            provider = "none"
        }

        kubernetes_version = "v${var.k8s_version}-rancher1-1"
        ingress {
            provider = "none"
        }

        upgrade_strategy {
            drain = false
            max_unavailable_controlplane = "1"
            max_unavailable_worker       = "10%"
        }
  }
}




resource "paperspace_autoscaling_group" "main" {
    for_each = local.asg_types
    
    name = "${var.cluster_handle}-${each.key}"
    cluster_id = var.cluster_handle
    machine_type = each.key 
    template_id = each.value.type == "cpu" ? var.machine_template_id_cpu : var.machine_template_id_gpu
    max = local.asg_max_sizes[each.key]
    min = local.asg_min_sizes[each.key]
    network_id = paperspace_network.network.handle
    startup_script_id = paperspace_script.autoscale.id
}

resource "paperspace_script" "autoscale" {
    name = "Autoscale cluster"
    description = "Autoscales cluster"
    script_text = <<EOF
        #!/usr/bin/env bash

        sudo su -

        until docker ps -a || (( count++ >= 30 )); do echo "Check if docker is up..."; sleep 2; done

        usermod -G docker paperspace

        echo "${tls_private_key.ssh_key.public_key_openssh}" >> /home/paperspace/.ssh/authorized_keys
        export MACHINE_ID=`curl https://metadata.paperspace.com/meta-data/machine | grep hostname | sed 's/^.*: "\(.*\)".*/\1/'` 
        curl -H 'Content-Type:application/json' -H 'X-API-Key: ${var.cluster_apikey}' -XPOST '${var.api_host}/clusterMachines/register' -d '{"clusterId":"${var.cluster_handle}", "machineId":"$MACHINE_ID"}'
    EOF
    is_enabled = true
    run_once = true
}

resource "null_resource" "register_managed_cluster_network" {
    provisioner "local-exec" {
        command = <<EOF
            curl -H 'Content-Type:application/json' -H 'X-API-Key: ${var.cluster_apikey}' -XPOST '${var.api_host}/clusters/updateCluster' -d '{"id":"${var.cluster_handle}", "attributes":{"networkId":"${paperspace_network.network.handle}"}}'
        EOF
    }
}

resource "null_resource" "register_managed_cluster_machine_main" {
    provisioner "local-exec" {
        command = <<EOF
            curl -H 'Content-Type:application/json' -H 'X-API-Key: ${var.cluster_apikey}' -XPOST '${var.api_host}/clusterMachines/register' -d '{"clusterId":"${var.cluster_handle}", "machineId":"${paperspace_machine.gradient_main.id}"}'
        EOF
    }
}

resource "cloudflare_record" "subdomain" {
    count = var.cloudflare_api_key == "" && var.cloudflare_email == "" && var.cloudflare_zone_id == "" ? 0 : 1
    zone_id = var.cloudflare_zone_id
    name    = var.domain
    value   = paperspace_machine.gradient_main.public_ip_address
    type    = "A"
    ttl     = 3600
    proxied = false
}

resource "cloudflare_record" "subdomain_wildcard" {
    count = var.cloudflare_api_key == "" && var.cloudflare_email == "" && var.cloudflare_zone_id == "" ? 0 : 1
    zone_id = var.cloudflare_zone_id
    name    = "*.${var.domain}"
    value   = paperspace_machine.gradient_main.public_ip_address
    type    = "A"
    ttl     = 3600
    proxied = false
}

output "main_node_public_ip_address" {
  value = paperspace_machine.gradient_main.public_ip_address
}

output "network_handle" {
    value = paperspace_network.network.handle
}
