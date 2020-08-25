variable "cluster_api_key" {
  description = "Cluster API key"
}

variable "is_managed" {
  type        = bool
  description = "Is PS Cloud cluster managed by Paperspace"
  default     = false
}
