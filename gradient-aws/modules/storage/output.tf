output "shared_storage_dns_name" {
  value = aws_efs_file_system.main[0].dns_name
}