locals {
    cluster_autoscaler_cloudprovider = var.is_managed ? "paperspace" : ""
    cluster_autoscaler_enabled = var.is_managed ? true : false
}

module "pks" {
  source = "../pks"

  # TODO fill in and add back variables
  admin_email        = ""
  admin_user_api_key = ""
  autoscaling_groups = []
  cloudflare         = {}
  cluster_api_key    = ""
  cluster_id         = ""
  master             = {}
  name               = ""
  team_id            = ""
  workers            = []
}

# TODO fill out from pks output
provider "kubernetes" {
  host     = module.kubernetes.k8s_host
  username = module.kubernetes.k8s_username

  client_certificate     = module.kubernetes.k8s_client_certificate
  client_key             = module.kubernetes.k8s_client_key
  cluster_ca_certificate = module.kubernetes.k8s_cluster_ca_certificate
  load_config_file       = false
}

# TODO remove
module "gradient_metal" {
    source = "../gradient-metal"

    name = var.name

    amqp_hostname = var.amqp_hostname

    artifacts_access_key_id = var.artifacts_access_key_id
    artifacts_path = var.artifacts_path
    artifacts_secret_access_key = var.artifacts_secret_access_key
    sentry_dsn = var.sentry_dsn

    cluster_autoscaler_autoscaling_groups = [for autoscaling_group in paperspace_autoscaling_group.main : {
        min: autoscaling_group.min
        max: autoscaling_group.max
        name: autoscaling_group.id
    }]
    cluster_autoscaler_cloudprovider = local.cluster_autoscaler_cloudprovider
    cluster_autoscaler_enabled = local.cluster_autoscaler_enabled
    cluster_handle = var.cluster_handle
  cluster_apikey                   = var.cluster_api_key

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

// Gradient
module "gradient_processing" {
  source  = "../modules/gradient-processing"
  enabled = module.kubernetes.k8s_host == "" ? false : true

  # TODO fill out correctly
  amqp_hostname                         = var.amqp_hostname
  amqp_port                             = var.amqp_port
  amqp_protocol                         = var.amqp_protocol
  artifacts_access_key_id               = var.artifacts_access_key_id
  artifacts_object_storage_endpoint     = var.artifacts_object_storage_endpoint
  artifacts_path                        = var.artifacts_path
  artifacts_secret_access_key           = var.artifacts_secret_access_key
  chart                                 = var.gradient_processing_chart
  cluster_apikey                        = var.cluster_apikey
  cluster_autoscaler_autoscaling_groups = var.cluster_autoscaler_autoscaling_groups
  cluster_autoscaler_cloudprovider      = var.cluster_autoscaler_cloudprovider
  cluster_autoscaler_enabled            = var.cluster_autoscaler_enabled
  cluster_handle                        = var.cluster_handle
  domain                                = var.domain

  helm_repo_username      = var.helm_repo_username
  helm_repo_password      = var.helm_repo_password
  helm_repo_url           = var.helm_repo_url
  elastic_search_host     = var.elastic_search_host
  elastic_search_index    = var.elastic_search_index
  elastic_search_password = var.elastic_search_password
  elastic_search_port     = var.elastic_search_port
  elastic_search_user     = var.elastic_search_user

  label_selector_cpu       = var.cpu_selector
  label_selector_gpu       = var.gpu_selector
  letsencrypt_dns_name     = var.letsencrypt_dns_name
  letsencrypt_dns_settings = var.letsencrypt_dns_settings
  // Use shared storage by default for now
  local_storage_server        = var.local_storage_server == "" ? var.shared_storage_server : var.local_storage_server
  local_storage_path          = var.local_storage_path == "" ? var.shared_storage_path : var.local_storage_path
  local_storage_type          = var.local_storage_type == "" ? local.shared_storage_type : var.local_storage_type
  logs_host                   = var.logs_host
  gradient_processing_version = var.gradient_processing_version
  name                        = var.name
  sentry_dsn                  = var.sentry_dsn
  service_pool_name           = local.service_pool_name
  shared_storage_server       = var.shared_storage_server
  shared_storage_path         = var.shared_storage_path
  shared_storage_type         = local.shared_storage_type
  tls_cert                    = var.tls_cert
  tls_key                     = var.tls_key
  use_pod_anti_affinity       = var.use_pod_anti_affinity

  providers = {
    kubernetes = kubernetes
}
}
