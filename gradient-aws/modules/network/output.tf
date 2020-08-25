output "nat_ips" {
  value = aws_eip.nat.*.public_ip
}

output "private_route_table_ids" {
  value = module.vpc.private_route_table_ids
}

output "private_subnet_ids" {
  value = module.vpc.private_subnets
}

output "private_security_group_id" {
  value = aws_security_group.private.id
}

output "public_route_table_ids" {
  value = module.vpc.public_route_table_ids
}

output "public_security_group_id" {
  value = aws_security_group.public.id
}

output "public_subnet_ids" {
  value = module.vpc.public_subnets
}

output "vpc_id" {
  value = module.vpc.vpc_id
}