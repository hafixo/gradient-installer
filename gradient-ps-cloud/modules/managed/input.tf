variable "api_host" {
    description = "api host"
    default = "api.paperspace.io"
}

variable "asg_max_sizes" {
    description = "Autoscaling Group max sizes"
}

variable "asg_min_sizes" {
    description = "Autoscaling Group min sizes"
}

variable "cloudflare_api_key" {
    description = "Cloudflare API key"
}
variable "cloudflare_email" {
    description = "Cloudflare email"
}
variable "cloudflare_zone_id" {
    description = "Cloudflare zone id"
}

variable "cluster_apikey" {
    description = "Gradient cluster API key"
}
variable "cluster_handle" {
    description = "Gradient cluster API handle"
}

variable "cpu_worker_nodes" {
    description = "Paperspace cpu machines"
    type = list
}

variable "domain" {
    description = "Domain used to host gradient"
}

variable "gpu_worker_nodes" {
    description = "Paperspace gpu machines"
    type = list
}

variable "machine_template_id_cpu" {
    description = "CPU template id"
}
variable "machine_template_id_gpu" {
    description = "GPU template id"
}

variable "main_node" {
    description = "Paperspace machine for main node"
    type = object({
        id = string
        public_ip_address = string
    })
}

variable "network_handle" {
    description = "Paperspace network handle"
}

variable "ssh_public_key" {
    description = "Public SSH key"
}