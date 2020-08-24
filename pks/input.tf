variable "admin_user_api_key" {
  type        = string
  description = "Paperspace admin API key"
}

variable "admin_email" {
  type        = string
  description = "Paperspace admin API email"
}

variable "api_host" {
  type        = string
  description = "api host"
  default     = "api.paperspace.io"
}

variable "autoscaling_groups" {
  type = list(object({
    machine_type : string
    template_id : string
    max : number
    min : number
  }))
}

variable "cloudflare" {
  type = object({
    api_key : string
    domain : string
    email : string
    is_proxied : string
    zone_id : string
  })
}

variable "cluster_api_key" {
  type        = string
  description = "Cluster API key"
}

variable "cluster_id" {
  type        = string
  description = "Cluster id"
}

variable "is_managed" {
  type        = bool
  description = "Is PS Cloud cluster managed by Paperspace"
  default     = false
}

variable "name" {
  type        = string
  description = "Cluster name"
}

variable "master" {
  type = object({
    machine_type : string
    machine_storage : number
    template_id : string
  })
}

variable "region" {
  type        = string
  description = "Cloud region"
  default     = "East Coast (NY2)"
}

variable "team_id" {
  type        = string
  description = "Cluster team id"
}

variable "workers" {
  type = list(object({
    machine_type : string
    machine_storage : number
    template_id : string
  }))
}
