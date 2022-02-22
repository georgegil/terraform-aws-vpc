output "vpc" {
  description = "VPC ID, CIDR, and any other details required as a sub attribute."
  value       = aws_vpc.vpc
}

output "public_subnet" {
  description = "Subnet ID, CIDR, and any other details required as a sub attribute of Public subnets."
  value       = aws_subnet.public
}

output "platforms_subnet" {
  description = "Subnet ID, CIDR, and any other details required as a sub attribute of Platforms services subnets."
  value       = aws_subnet.platforms
}

output "private-dynamic_subnet" {
  description = "Subnet ID, CIDR, and any other details required as a sub attribute of general Private subnets."
  value       = aws_subnet.private_dynamic
}

output "private-static_subnet" {
  description = "Subnet ID, CIDR, and any other details required as a sub attribute of Private subnets that require a static IP address."
  value       = aws_subnet.private_static
}

output "private_rds_subnet" {
  description = "Subnet ID, CIDR, and any other details required as a sub attribute of subnets allocated to RDS resources."
  value       = aws_subnet.rds
}

output "public_routing_table" {
  description = "The public routing table ID."
  value       = aws_route_table.public.id
}

output "private_routing_table" {
  description = "The private routing table ID."
  value       = aws_route_table.private.id
}

output "transit_gateway_id" {
  description = "The Transit gateway ID"
  value       = var.tgw_id != null ? null : aws_ec2_transit_gateway.tgw[0].id
}
