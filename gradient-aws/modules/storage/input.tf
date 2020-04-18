variable "enable" {
    type = bool
    description = "If module should be enabled"
}

variable "name" {
    description = "Name"
}

variable "security_group_ids" {
    description = "Security groups ids for shared storage"
}

variable "subnet_ids" {
    description = "Subnet ids for shared storage"
}