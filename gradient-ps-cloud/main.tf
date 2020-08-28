terraform {
    required_providers {
        cloudflare = {
            source  = "cloudflare/cloudflare"
            version = "~> 2.10.0"
        }
    }
}

locals {
    autoscaling_groups = var.is_managed ? module.managed[0].autoscaling_groups : []
    cluster_autoscaler_cloudprovider = var.is_managed ? "paperspace" : ""
    cluster_autoscaler_enabled = var.is_managed ? true : false

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
    is_managed = var.is_managed

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

resource "paperspace_machine" "gradient_workers_cpu" {
    depends_on = [
        paperspace_script.add_public_ssh_key,
        tls_private_key.ssh_key,
    ]

    count = var.machine_count_worker_cpu
    region = var.region
    name = "${var.cluster_handle}-${var.name}-worker[-cpu-${count.index}"
    machine_type = var.machine_type_worker_cpu
    size = var.machine_storage_worker_cpu
    billing_type = "hourly"
    assign_public_ip = true
    template_id = var.machine_template_id_cpu
    user_id = data.paperspace_user.admin.id
    team_id = data.paperspace_user.admin.team_id
    script_id = paperspace_script.add_public_ssh_key.id
    network_id = paperspace_network.network.handle
    live_forever = true
    is_managed = var.is_managed

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
            -i '${self.public_ip_address},' \
            ${path.module}/ansible/playbook-gradient-metal-ps-cloud-node.yaml
        EOF
    }
}

resource "paperspace_machine" "gradient_workers_gpu" {
    depends_on = [
        paperspace_script.add_public_ssh_key,
        tls_private_key.ssh_key,
    ]

    count = var.machine_count_worker_gpu
    region = var.region
    name = "${var.cluster_handle}-${var.name}-worker-gpu-${count.index}"
    machine_type = var.machine_type_worker_gpu
    size = var.machine_storage_worker_gpu
    billing_type = "hourly"
    assign_public_ip = true
    template_id = var.machine_template_id_gpu
    user_id = data.paperspace_user.admin.id
    team_id = data.paperspace_user.admin.team_id
    script_id = paperspace_script.add_public_ssh_key.id
    network_id = paperspace_network.network.handle
    live_forever = true
    is_managed = var.is_managed

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
            -i '${self.public_ip_address},' \
            ${path.module}/ansible/playbook-gradient-metal-ps-cloud-node.yaml
        EOF
    }
}

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

module "managed" {
    count = var.is_managed ? 1 : 0
    source = "./modules/managed"

    api_host = var.api_host
    asg_min_sizes = var.asg_min_sizes
    asg_max_sizes = var.asg_max_sizes
    cloudflare_api_key = var.cloudflare_api_key
    cloudflare_email = var.cloudflare_email
    cloudflare_zone_id = var.cloudflare_zone_id
    cluster_apikey = var.cluster_apikey
    cluster_handle = var.cluster_handle
    domain = var.domain
    cpu_worker_nodes = paperspace_machine.gradient_workers_cpu
    gpu_worker_nodes = paperspace_machine.gradient_workers_gpu
    network_handle = paperspace_network.network.handle
    machine_template_id_cpu = var.machine_template_id_cpu
    machine_template_id_gpu = var.machine_template_id_gpu
    main_node = paperspace_machine.gradient_main
    ssh_public_key = tls_private_key.ssh_key.public_key_openssh

    providers = {
        cloudflare = cloudflare
    }
}

output "main_node_public_ip_address" {
  value = paperspace_machine.gradient_main.public_ip_address
}

output "network_handle" {
    value = paperspace_network.network.handle
}
