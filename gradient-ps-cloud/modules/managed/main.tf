locals {
    asg_types = {
        "cpu"={},
        "gpu"={},
    }
    asg_max_sizes = merge({
        "cpu"="10",
        "gpu"="10"
    }, var.asg_min_sizes)

    asg_min_sizes = merge({
        "cpu"="0",
        "gpu"="0"
    }, var.asg_min_sizes)

    cluster_autoscaler_cloudprovider = var.is_managed ? "paperspace" : ""
    cluster_autoscaler_enabled = var.is_managed ? true : false
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
    machine_type = each.key == "cpu" ? var.machine_type_worker_cpu : var.machine_type_worker_gpu
    template_id = each.key == "cpu" ? var.machine_template_id_cpu : var.machine_template_id_gpu
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
    depends_on = [module.gradient_metal]

    provisioner "local-exec" {
        command = <<EOF
            curl -H 'Content-Type:application/json' -H 'X-API-Key: ${var.cluster_apikey}' -XPOST '${var.api_host}/clusters/updateCluster' -d '{"id":"${var.cluster_handle}", "attributes":{"networkId":"${paperspace_network.network.id}"}}'
        EOF
    }
}

resource "null_resource" "register_managed_cluster_machine_main" {
    depends_on = [module.gradient_metal]

    provisioner "local-exec" {
        command = <<EOF
            curl -H 'Content-Type:application/json' -H 'X-API-Key: ${var.cluster_apikey}' -XPOST '${var.api_host}/clusterMachines/register' -d '{"clusterId":"${var.cluster_handle}", "machineId":"${paperspace_machine.gradient_main.id}"}'
        EOF
    }
}

resource "null_resource" "register_managed_cluster_machine_workers_cpu" {
    depends_on = [module.gradient_metal]

    count = var.machine_count_worker_cpu

    provisioner "local-exec" {
        command = <<EOF
            curl -H 'Content-Type:application/json' -H 'X-API-Key: ${var.cluster_apikey}' -XPOST '${var.api_host}/clusterMachines/register' -d '{"clusterId":"${var.cluster_handle}", "machineId":"${paperspace_machine.gradient_workers_cpu[count.index].id}"}'
        EOF
    }
}

resource "null_resource" "register_managed_cluster_machine_workers_gpu" {
    depends_on = [module.gradient_metal]

    count = var.machine_count_worker_gpu

    provisioner "local-exec" {
        command = <<EOF
            curl -H 'Content-Type:application/json' -H 'X-API-Key: ${var.cluster_apikey}' -XPOST '${var.api_host}/clusterMachines/register' -d '{"clusterId":"${var.cluster_handle}", "machineId":"${paperspace_machine.gradient_workers_gpu[count.index].id}"}'
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
    proxied = var.is_proxied
}

resource "cloudflare_record" "subdomain_wildcard" {
    count = var.cloudflare_api_key == "" && var.cloudflare_email == "" && var.cloudflare_zone_id == "" ? 0 : 1
    zone_id = var.cloudflare_zone_id
    name    = "*.${var.domain}"
    value   = paperspace_machine.gradient_main.public_ip_address
    type    = "A"
    ttl     = 3600
    proxied = var.is_proxied
}
