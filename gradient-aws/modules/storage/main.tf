locals {
    enable_count = var.enable ? 1 : 0
}

resource "aws_efs_file_system" "main" {
    count = local.enable_count

    creation_token = var.name

    tags = {
        Name = var.name
    }
}

resource "aws_efs_mount_target" "main" {
    count = local.enable_count == 1 ? length(var.subnet_ids) : 0

    file_system_id = aws_efs_file_system.main[0].id
    security_groups = var.security_group_ids
    subnet_id      = var.subnet_ids[count.index]
}