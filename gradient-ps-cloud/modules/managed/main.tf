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
}

terraform {
    required_providers {
        cloudflare = {
            source  = "cloudflare/cloudflare"
            version = "~> 2.10.0"
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
    network_id = var.network_handle
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

        echo "${var.ssh_public_key}" >> /home/paperspace/.ssh/authorized_keys
        export MACHINE_ID=`curl https://metadata.paperspace.com/meta-data/machine | grep hostname | sed 's/^.*: "\(.*\)".*/\1/'` 
        curl -H 'Content-Type:application/json' -H 'X-API-Key: ${var.cluster_apikey}' -XPOST '${var.api_host}/clusterMachines/register' -d '{"clusterId":"${var.cluster_handle}", "machineId":"$MACHINE_ID"}'
    EOF
    is_enabled = true
    run_once = true
}

resource "null_resource" "register_managed_cluster_network" {
    provisioner "local-exec" {
        command = <<EOF
            curl -H 'Content-Type:application/json' -H 'X-API-Key: ${var.cluster_apikey}' -XPOST '${var.api_host}/clusters/updateCluster' -d '{"id":"${var.cluster_handle}", "attributes":{"networkId":"${var.network_handle}"}}'
        EOF
    }
}

resource "null_resource" "register_managed_cluster_machine_main" {
    provisioner "local-exec" {
        command = <<EOF
            curl -H 'Content-Type:application/json' -H 'X-API-Key: ${var.cluster_apikey}' -XPOST '${var.api_host}/clusterMachines/register' -d '{"clusterId":"${var.cluster_handle}", "machineId":"${var.main_node.id}"}'
        EOF
    }
}

resource "null_resource" "register_managed_cluster_machine_workers_cpu" {
    count = length(var.cpu_worker_nodes)

    provisioner "local-exec" {
        command = <<EOF
            curl -H 'Content-Type:application/json' -H 'X-API-Key: ${var.cluster_apikey}' -XPOST '${var.api_host}/clusterMachines/register' -d '{"clusterId":"${var.cluster_handle}", "machineId":"${var.cpu_worker_nodes[count.index].id}"}'
        EOF
    }
}

resource "null_resource" "register_managed_cluster_machine_workers_gpu" {
    count = length(var.gpu_worker_nodes)

    provisioner "local-exec" {
        command = <<EOF
            curl -H 'Content-Type:application/json' -H 'X-API-Key: ${var.cluster_apikey}' -XPOST '${var.api_host}/clusterMachines/register' -d '{"clusterId":"${var.cluster_handle}", "machineId":"${var.gpu_worker_nodes[count.index].id}"}'
        EOF
    }
}


resource "cloudflare_record" "subdomain" {
    count = var.cloudflare_api_key == "" && var.cloudflare_email == "" && var.cloudflare_zone_id == "" ? 0 : 1
    zone_id = var.cloudflare_zone_id
    name    = var.domain
    value   = var.main_node.public_ip_address
    type    = "A"
    ttl     = 3600
    proxied = false
}

resource "cloudflare_record" "subdomain_wildcard" {
    count = var.cloudflare_api_key == "" && var.cloudflare_email == "" && var.cloudflare_zone_id == "" ? 0 : 1
    zone_id = var.cloudflare_zone_id
    name    = "*.${var.domain}"
    value   = var.main_node.public_ip_address
    type    = "A"
    ttl     = 3600
    proxied = false
}

output "autoscaling_groups" {
    value = paperspace_autoscaling_group.main
}