##########
#generic
##########

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_region" "current" {}

locals {
  region_code       = upper(split("-", data.aws_availability_zones.available.zone_ids[0])[0])
  environment       = upper(var.tags.Environment)
  vpc_environment   = var.vpc_prefix == null ? "${local.environment}${local.region_code}VPC" : "${local.environment}${local.region_code}${var.vpc_prefix}VPC"
  dhcp_environment  = "${local.environment}${local.region_code}-dhcp-options"
  igw_environment   = "${local.environment}${local.region_code}-IGW"
  vgw_environment   = "${local.environment}${local.region_code}-VGW"
  PublicRoute       = "${local.environment}${local.region_code}PublicRoutingTable"
  PrivateRoute      = "${local.environment}${local.region_code}PrivateRoutingTable"
  nimsoft_sg_name   = "SS-Groups-Monitor-${local.region_code}-${local.environment}"
  dns_sg_name       = "Route53-DNSRouting-${local.region_code}-${local.environment}"
  storgw_sg_name    = "SS-Groups-StorGw-${local.region_code}-${local.environment}"
  apigw_sg_name     = "SS-Groups-APIGw-${local.region_code}-${local.environment}"
  s3_intf_sg_name   = "SS-Groups-S3Intf-${local.region_code}-${local.environment}"
  efsdsintf_sg_name = "SS-Groups-EFSDSIntf-${local.region_code}-${local.environment}"

  # subnet calculation
  vpc_cidr        = var.vpc_cidr
  vpc_cidr_bit    = tonumber(split("/", local.vpc_cidr)[1])
  subnetsize_bit  = var.subnet_size - local.vpc_cidr_bit
  std_subnets_bit = var.custom_subnets == null ? local.subnetsize_bit : 25 - local.vpc_cidr_bit

  ##### custom subnet conditional
  custom_subnets = var.custom_subnets == null ? {} : var.custom_subnets


  #{ for s in var.custom_subnets : s => var.custom_subnets }


  #### direct connect gateway routing
  dx_gateway_cidr = var.dx_gateway_cidr != null ? var.dx_gateway_cidr : [var.vpc_cidr]

  ####### Subnets #######
  PublicSubnet              = "${local.environment}${local.region_code}PublicSubnet"
  PrivateRDSSubnet          = "${local.environment}${local.region_code}PrivateRDSSubnet"
  PlatformServicesSubnet    = "${local.environment}${local.region_code}PlatformServicesSubnet"
  PlatformServicesSubnetNum = var.custom_subnets == null ? 6 : 3
  PrivateDynamicSubnet      = "${local.environment}${local.region_code}PrivateDynamicSubnet"
  PrivateStaticSubnet       = "${local.environment}${local.region_code}PrivateStaticSubnet"


  
}

##################
#VPC-FlowLogs
##################

resource "aws_cloudwatch_log_group" "vpc_logs" {
  name              = "${local.vpc_environment}-cloud-watch-logs"
  retention_in_days = "30"

  tags = var.tags
}

resource "aws_flow_log" "vpc_log" {
  iam_role_arn    = ""
  log_destination = aws_cloudwatch_log_group.vpc_logs.arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.vpc.id

  tags = var.tags
}

resource "aws_flow_log" "s3_log" {
  log_destination      = "arn:aws:s3:::global-logs/vpcflowlogs"
  log_destination_type = "s3"
  traffic_type         = "ALL"
  vpc_id               = aws_vpc.vpc.id

  tags = var.tags
}

######
# VPC
######
resource "aws_vpc" "vpc" {
  cidr_block                       = local.vpc_cidr
  enable_dns_hostnames             = true
  enable_dns_support               = true
  instance_tenancy                 = "default"
  assign_generated_ipv6_cidr_block = false

  tags = merge({ "Name" = local.vpc_environment }, var.tags)
}

###################
# DHCP Options Set
###################
resource "aws_vpc_dhcp_options" "dhcp" {
  domain_name         = var.domain_search_suffix == null ? var.domain_name[0] : var.domain_search_suffix
  domain_name_servers = ["AmazonProvidedDNS"]
  ntp_servers         = var.dns_servers

  tags = merge({ "Name" = local.dhcp_environment }, var.tags)
}

resource "aws_vpc_dhcp_options_association" "dhcp_link" {
  vpc_id          = aws_vpc.vpc.id
  dhcp_options_id = aws_vpc_dhcp_options.dhcp.id
}

###################
# DNS routing
###################

resource "aws_route53_resolver_endpoint" "dns" {
  security_group_ids = [aws_security_group.dns_sg.id]
  name               = "${local.region_code}-dns"
  direction          = "OUTBOUND"

  dynamic "ip_address" {
    for_each = aws_subnet.platforms[*].id
    content {
      subnet_id = ip_address.value
    }
  }

  tags = var.tags
}

resource "aws_route53_resolver_rule" "dns_fwd" {
  count                = length(var.domain_name)
  domain_name          = var.domain_name[count.index]
  name                 = replace("${local.region_code}-${var.domain_name[count.index]}", ".", "-")
  rule_type            = "FORWARD"
  resolver_endpoint_id = aws_route53_resolver_endpoint.dns.id

  dynamic "target_ip" {
    for_each = var.dns_servers
    content {
      ip = target_ip.value
    }
  }

  tags = var.tags
}

resource "aws_route53_resolver_rule_association" "dns_routing_vpc" {
  count            = length(var.domain_name)
  resolver_rule_id = element(aws_route53_resolver_rule.dns_fwd[*].id, count.index)
  vpc_id           = aws_vpc.vpc.id
}

resource "aws_route53_resolver_rule" "r_dns_fwd" {
  domain_name          = "10.in-addr.arpa"
  name                 = replace("${local.region_code}-${"10.in-addr.arpa"}", ".", "-")
  rule_type            = "FORWARD"
  resolver_endpoint_id = aws_route53_resolver_endpoint.dns.id

  dynamic "target_ip" {
    for_each = var.dns_servers
    content {
      ip = target_ip.value
    }
  }

  tags = var.tags
}

resource "aws_route53_resolver_rule_association" "r_dns_routing_vpc" {
  resolver_rule_id = aws_route53_resolver_rule.r_dns_fwd.id
  vpc_id           = aws_vpc.vpc.id
}


###################
# Internet Gateway
###################
resource "aws_internet_gateway" "internet_gw" {
  vpc_id = aws_vpc.vpc.id

  tags = merge({ "Name" = local.igw_environment }, var.tags)
}


##################
#Create Transit Gateway
##################

resource "aws_ec2_transit_gateway" "tgw" {
  count                           = var.tgw_id != null ? 0 : 1
  amazon_side_asn                 = var.amazon_side_asn_tgw
  auto_accept_shared_attachments  = "disable"
  default_route_table_association = "enable"
  default_route_table_propagation = "enable"
  dns_support                     = "enable"
  vpn_ecmp_support                = "enable"

  tags = merge({ "Name" = "${local.environment}${local.region_code}TGW" }, var.tags)
}

resource "aws_ec2_transit_gateway_route" "TGWVPCRT" {
  count                          = var.tgw_id != null ? 0 : 1
  destination_cidr_block         = var.vpc_cidr
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.transit_attach[0].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway.tgw[0].association_default_route_table_id
}

########################
# Transit Gateway VPC Attach
########################

resource "aws_ec2_transit_gateway_vpc_attachment" "transit_attach" {
  count              = var.tgw_id != null ? 0 : 1
  vpc_id             = aws_vpc.vpc.id
  subnet_ids         = aws_subnet.platforms[*].id
  transit_gateway_id = aws_ec2_transit_gateway.tgw[0].id

  tags = merge({ "Name" = "${local.vpc_environment}-attach" }, var.tags)
}

resource "aws_ec2_transit_gateway_vpc_attachment" "transit_x-attach" {
  count              = var.tgw_id != null ? 1 : 0
  vpc_id             = aws_vpc.vpc.id
  subnet_ids         = aws_subnet.platforms[*].id
  transit_gateway_id = var.tgw_id

  tags = merge({ "Name" = "${local.vpc_environment}-x-attach" }, var.tags)
}

################
# Publiс Subnets
################
resource "aws_subnet" "public" {
  count                   = 3
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = cidrsubnet(local.vpc_cidr, local.std_subnets_bit, count.index + 0)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  tags                    = merge({ Name = format("${local.PublicSubnet}AZ%01d", count.index + 1) }, var.tags)
}

###############
#Publiс routes
###############
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.vpc.id

  tags = merge({ "Name" = local.PublicRoute }, var.tags)
}

resource "aws_route" "public_internet_gateway" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.internet_gw.id
  timeouts {
    create = "5m"
  }
}

resource "aws_route_table_association" "public" {
  count          = 3
  subnet_id      = element(aws_subnet.public.*.id, count.index)
  route_table_id = aws_route_table.public.id
}

#################
# Private Subnets
#################

resource "aws_subnet" "platforms" {
  count             = 3
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = cidrsubnet(local.vpc_cidr, local.std_subnets_bit, count.index + local.PlatformServicesSubnetNum)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  lifecycle {
    # Ignore tags added by kubernetes
    ignore_changes = [tags.kubernetes, tags.SubnetType]
  }

  tags = merge({ "Name" = format("${local.PlatformServicesSubnet}AZ%01d", count.index + 1) }, var.tags)
}

resource "aws_subnet" "private_dynamic" {
  count             = var.custom_subnets == null ? 3 : 0
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = cidrsubnet(local.vpc_cidr, local.subnetsize_bit, count.index + 9)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  lifecycle {
    # Ignore tags added by kubernetes
    ignore_changes = [tags.kubernetes, tags.SubnetType]
  }

  tags = merge({ "Name" = format("${local.PrivateDynamicSubnet}AZ%01d", count.index + 1) }, var.tags)
}

resource "aws_subnet" "private_static" {
  count             = var.custom_subnets == null ? 3 : 0
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = cidrsubnet(local.vpc_cidr, local.subnetsize_bit, count.index + 12)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  lifecycle {
    # Ignore tags added by kubernetes
    ignore_changes = [tags.kubernetes, tags.SubnetType]
  }

  tags = merge({ "Name" = format("${local.PrivateStaticSubnet}AZ%01d", count.index + 1) }, var.tags)
}

#################
#RDS Subnets
#################

resource "aws_subnet" "rds" {
  count             = var.custom_subnets == null ? 3 : 0
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = cidrsubnet(local.vpc_cidr, local.subnetsize_bit, count.index + 3)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = merge({ "Name" = format("${local.PrivateRDSSubnet}AZ%01d", count.index + 1) }, var.tags)
}

resource "aws_db_subnet_group" "rds_dedicate_subnet" {
  count      = var.custom_subnets == null ? 1 : 0
  name       = lower(local.PrivateRDSSubnet)
  subnet_ids = aws_subnet.rds[*].id

  tags = merge({ "Name" = "RDS_Subnets" }, var.tags)
}

#################
#custom subnets
#################

resource "aws_subnet" "custom" {
  for_each = local.custom_subnets
  #count             = var.custom_subnets == null ? 3 : 0
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = each.value.cidr
  availability_zone = each.value.az

  tags = merge({ "Name" = each.key }, var.tags)
}

###########################
#Custom Subnet route tables
##########################

resource "aws_route_table_association" "custom_subnet" {
  for_each       = local.custom_subnets
  subnet_id      = aws_subnet.custom[each.key].id
  route_table_id = aws_route_table.private.id
}

#################
#Private routes
#################
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.vpc.id

  tags = merge({ "Name" = local.PrivateRoute }, var.tags)
}

resource "aws_route" "transit_egress" {
  count                  = var.tgw_id != null ? 0 : 1
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  transit_gateway_id     = aws_ec2_transit_gateway.tgw[0].id
  timeouts {
    create = "5m"
  }
}

resource "aws_route" "transit_corp" {
  count                  = var.tgw_id != null ? 0 : 1
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "10.0.0.0/8"
  transit_gateway_id     = aws_ec2_transit_gateway.tgw[0].id
  timeouts {
    create = "5m"
  }
}

resource "aws_route" "transit_corp_gp" {
  count                  = var.tgw_id != null ? 0 : 1
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "172.16.0.0/12"
  transit_gateway_id     = aws_ec2_transit_gateway.tgw[0].id
  timeouts {
    create = "5m"
  }
}

resource "aws_route" "transit_egress_x" {
  count                  = var.tgw_id != null ? 1 : 0
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  transit_gateway_id     = var.tgw_id
  timeouts {
    create = "5m"
  }
}

resource "aws_route" "transit_corp_x" {
  count                  = var.tgw_id != null ? 1 : 0
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "10.0.0.0/8"
  transit_gateway_id     = var.tgw_id
  timeouts {
    create = "5m"
  }
}

resource "aws_route" "transit_corp_gp_x" {
  count                  = var.tgw_id != null ? 1 : 0
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "172.16.0.0/12"
  transit_gateway_id     = var.tgw_id
  timeouts {
    create = "5m"
  }
}

resource "aws_route_table_association" "platforms" {
  count          = 3
  subnet_id      = element(aws_subnet.platforms.*.id, count.index)
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_dynamic" {
  count          = var.custom_subnets == null ? 3 : 0
  subnet_id      = element(aws_subnet.private_dynamic.*.id, count.index)
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_static" {
  count          = var.custom_subnets == null ? 3 : 0
  subnet_id      = element(aws_subnet.private_static.*.id, count.index)
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "serverless_rds" {
  count          = var.custom_subnets == null ? 3 : 0
  subnet_id      = element(aws_subnet.rds.*.id, count.index)
  route_table_id = aws_route_table.private.id
}


######### Security Groups ########

resource "aws_security_group" "dns_sg" {
  name        = local.dns_sg_name
  description = "Allow communication to DNS servers"
  vpc_id      = aws_vpc.vpc.id

  tags = merge({ "Name" = local.dns_sg_name }, var.tags)
}

resource "aws_security_group_rule" "tcp_allow_dns" {
  type              = "egress"
  from_port         = 53
  to_port           = 53
  protocol          = "tcp"
  cidr_blocks       = ["10.0.0.0/8"]
  security_group_id = aws_security_group.dns_sg.id
}

resource "aws_security_group_rule" "udp_allow_dns" {
  type              = "egress"
  from_port         = 53
  to_port           = 53
  protocol          = "udp"
  cidr_blocks       = ["10.0.0.0/8"]
  security_group_id = aws_security_group.dns_sg.id
}

resource "aws_security_group_rule" "dns_sg" {
  type              = "ingress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["10.0.0.0/8"]
  security_group_id = aws_security_group.dns_sg.id
}

resource "aws_security_group" "nimsoft_sg" {
  name        = local.nimsoft_sg_name
  description = "Allow communication from Nimsoft to client host"
  vpc_id      = aws_vpc.vpc.id

  tags = merge({ "Name" = local.nimsoft_sg_name }, var.tags)
}

resource "aws_security_group_rule" "default_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.nimsoft_sg.id
}

resource "aws_security_group" "storagegw_sg" {
  name        = local.storgw_sg_name
  description = "Created for Storage Gw VPC Endpoint"
  vpc_id      = aws_vpc.vpc.id

  tags = merge({ "Name" = local.storgw_sg_name }, var.tags)
}

resource "aws_security_group_rule" "storgw_sg_inbound" {
  type              = "ingress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.storagegw_sg.id
}

resource "aws_security_group_rule" "storgw_sg_outbound" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.storagegw_sg.id
}

resource "aws_security_group" "apigw_sg" {
  name        = local.apigw_sg_name
  description = "Created for API Gw VPC Endpoint"
  vpc_id      = aws_vpc.vpc.id

  tags = merge({ "Name" = local.apigw_sg_name }, var.tags)
}

resource "aws_security_group_rule" "apigw_sg_inbound" {
  type              = "ingress"
  from_port         = 0
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["10.0.0.0/8"]
  security_group_id = aws_security_group.apigw_sg.id
}

resource "aws_security_group_rule" "apigw_sg_outbound" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.apigw_sg.id
}

resource "aws_security_group" "s3_intf_sg" {
  name        = local.s3_intf_sg_name
  description = "Created for S3 Interface VPC Endpoint"
  vpc_id      = aws_vpc.vpc.id

  tags = merge({ "Name" = local.s3_intf_sg_name }, var.tags)
}

resource "aws_security_group_rule" "s3_intf_sg_inbound" {
  type              = "ingress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.s3_intf_sg.id
}

resource "aws_security_group_rule" "s3_intf_sg_outbound" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.s3_intf_sg.id
}

resource "aws_security_group" "efsdsintf_sg" {
  name        = local.efsdsintf_sg_name
  description = "Created for EFS Datasync VPC Endpoint"
  vpc_id      = aws_vpc.vpc.id

  tags = merge({ "Name" = local.efsdsintf_sg_name }, var.tags)
}

resource "aws_security_group_rule" "efsdsintf_sg_inbound" {
  type              = "ingress"
  from_port         = 443
  to_port           = 1064
  protocol          = "tcp"
  cidr_blocks       = ["10.0.0.0/8", "172.16.0.0/12"]
  security_group_id = aws_security_group.efsdsintf_sg.id
}

resource "aws_security_group_rule" "efsdsintf_sg_outbound" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.efsdsintf_sg.id
}

###########################
# Creating VPC S3 Endpoint
###########################

resource "aws_vpc_endpoint" "private-s3" {
  vpc_id       = aws_vpc.vpc.id
  service_name = "com.amazonaws.${data.aws_region.current.name}.s3"
  route_table_ids = [
    aws_route_table.private.id,
    aws_route_table.public.id
  ]
  tags   = merge({ "Name" = "${local.vpc_environment}-EP-S3" }, var.tags)
  policy = <<POLICY
{
    "Statement": [
        {
            "Action": "*",
            "Effect": "Allow",
            "Resource": "*",
            "Principal": "*"
        }
    ],
    "Version": "2008-10-17"
}
POLICY
}

#####################################
# Creating VPC S3 Interface Endpoint
#####################################

resource "aws_vpc_endpoint" "s3-intf" {
  vpc_id             = aws_vpc.vpc.id
  service_name       = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type  = "Interface"
  security_group_ids = [aws_security_group.s3_intf_sg.id]
  subnet_ids = [
    aws_subnet.platforms[0].id,
    aws_subnet.platforms[1].id,
    aws_subnet.platforms[2].id
  ]
  tags                = merge({ "Name" = "${local.vpc_environment}-EP-S3INTF" }, var.tags)
  private_dns_enabled = false
}

########################################
# Creating VPC Storage Gateway Endpoint
########################################

resource "aws_vpc_endpoint" "storgw-ep" {
  vpc_id             = aws_vpc.vpc.id
  service_name       = "com.amazonaws.${data.aws_region.current.name}.storagegateway"
  vpc_endpoint_type  = "Interface"
  security_group_ids = [aws_security_group.storagegw_sg.id]
  subnet_ids = [
    aws_subnet.platforms[0].id,
    aws_subnet.platforms[1].id,
    aws_subnet.platforms[2].id
  ]
  tags                = merge({ "Name" = "${local.vpc_environment}-EP-STORGW" }, var.tags)
  private_dns_enabled = true
}

########################################
# Creating VPC Elastic FileSystem Endpoint
########################################

resource "aws_vpc_endpoint" "efs-ep" {
  vpc_id             = aws_vpc.vpc.id
  service_name       = "com.amazonaws.${data.aws_region.current.name}.elasticfilesystem"
  vpc_endpoint_type  = "Interface"
  security_group_ids = [aws_security_group.storagegw_sg.id]
  subnet_ids = [
    aws_subnet.platforms[0].id,
    aws_subnet.platforms[1].id,
    aws_subnet.platforms[2].id
  ]
  tags                = merge({ "Name" = "${local.vpc_environment}-EP-EFS" }, var.tags)
  private_dns_enabled = true
  policy              = <<POLICY
{
    "Statement": [
        {
            "Action": "*",
            "Effect": "Allow",
            "Resource": "*",
            "Principal": "*"
        }
    ],
    "Version": "2008-10-17"
}
POLICY
}

#####################################
# Creating VPC API Gateway Endpoint
#####################################

resource "aws_vpc_endpoint" "apigw-ep" {
  vpc_id             = aws_vpc.vpc.id
  service_name       = "com.amazonaws.${data.aws_region.current.name}.execute-api"
  vpc_endpoint_type  = "Interface"
  security_group_ids = [aws_security_group.apigw_sg.id]
  subnet_ids = [
    aws_subnet.platforms[0].id,
    aws_subnet.platforms[1].id,
    aws_subnet.platforms[2].id
  ]
  tags                = merge({ "Name" = "${local.vpc_environment}-EP-APIGW" }, var.tags)
  private_dns_enabled = true
}

#####################################
# Creating VPC EFS DataSync Endpoint
#####################################

resource "aws_vpc_endpoint" "efsds-ep" {
  vpc_id             = aws_vpc.vpc.id
  service_name       = "com.amazonaws.${data.aws_region.current.name}.datasync"
  vpc_endpoint_type  = "Interface"
  security_group_ids = [aws_security_group.efsdsintf_sg.id]
  subnet_ids = [
    aws_subnet.platforms[0].id,
    aws_subnet.platforms[1].id,
    aws_subnet.platforms[2].id
  ]
  tags                = merge({ "Name" = "${local.vpc_environment}-EP-EFSDS" }, var.tags)
  private_dns_enabled = true
}

#############################
# Creating Direct Connect Gateway
#############################

resource "aws_dx_gateway" "DCG" {
  count           = var.amazon_side_asn_dcg != null ? 1 : 0
  amazon_side_asn = var.amazon_side_asn_dcg
  name            = "${local.environment}${local.region_code}DCG"
}

resource "aws_dx_gateway_association" "DCG-TGW" {
  count                 = var.amazon_side_asn_dcg != null ? 1 : 0
  dx_gateway_id         = aws_dx_gateway.DCG[0].id
  associated_gateway_id = aws_ec2_transit_gateway.tgw[0].id

  allowed_prefixes = local.dx_gateway_cidr

  timeouts {
    create = "30m"
    update = "30m"
    delete = "30m"
  }
}

data "aws_ec2_transit_gateway_dx_gateway_attachment" "TGWDCGattach" {
  count              = var.use_static_routing ? 1 : 0
  transit_gateway_id = aws_ec2_transit_gateway.tgw[0].id
  dx_gateway_id      = aws_dx_gateway.DCG[0].id

  depends_on = [aws_dx_gateway_association.DCG-TGW]

  tags = var.tags
}

resource "aws_ec2_transit_gateway_route" "TGWDefaRT" {
  count                          = var.use_static_routing ? 1 : 0
  destination_cidr_block         = "0.0.0.0/0"
  blackhole                      = false
  transit_gateway_attachment_id  = data.aws_ec2_transit_gateway_dx_gateway_attachment.TGWDCGattach[0].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway.tgw[0].association_default_route_table_id
}

resource "aws_ec2_transit_gateway_route" "TGWIntRT" {
  count                          = var.use_static_routing ? 1 : 0
  destination_cidr_block         = "10.0.0.0/8"
  blackhole                      = false
  transit_gateway_attachment_id  = data.aws_ec2_transit_gateway_dx_gateway_attachment.TGWDCGattach[0].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway.tgw[0].association_default_route_table_id
}

resource "aws_ec2_transit_gateway_route" "TGWIntRT2" {
  count                          = var.use_static_routing ? 1 : 0
  destination_cidr_block         = "172.16.0.0/12"
  blackhole                      = false
  transit_gateway_attachment_id  = data.aws_ec2_transit_gateway_dx_gateway_attachment.TGWDCGattach[0].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway.tgw[0].association_default_route_table_id
}

resource "aws_ec2_transit_gateway_route" "TGWIntRT3" {
  count                          = var.use_static_routing ? 1 : 0
  destination_cidr_block         = "192.168.0.0/16"
  blackhole                      = false
  transit_gateway_attachment_id  = data.aws_ec2_transit_gateway_dx_gateway_attachment.TGWDCGattach[0].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway.tgw[0].association_default_route_table_id
}


###############################################################
# Connect Transit gateway to additional Direct Connect Gateway
###############################################################

data "aws_dx_gateway" "dx_gw" {
  count = var.remote_dx_gateway_name != null ? length(var.remote_dx_gateway_name) : 0
  name  = var.remote_dx_gateway_name[count.index]
}

resource "aws_dx_gateway_association" "dxgw_tgw" {
  count                 = var.remote_dx_gateway_name != null ? length(var.remote_dx_gateway_name) : 0
  dx_gateway_id         = data.aws_dx_gateway.dx_gw[count.index].id
  associated_gateway_id = aws_ec2_transit_gateway.tgw[0].id

  allowed_prefixes = local.dx_gateway_cidr


  timeouts {
    create = "30m"
    update = "30m"
    delete = "30m"
  }
}


###############
#Creating Resource share
################

resource "aws_ram_resource_share" "share" {
  name                      = "${local.vpc_environment}-share"
  allow_external_principals = false

  tags = var.tags
}

resource "aws_ram_resource_association" "public-share" {
  count              = 3
  resource_arn       = aws_subnet.public[count.index].arn
  resource_share_arn = aws_ram_resource_share.share.id
}

resource "aws_ram_resource_association" "platforms-share" {
  count              = 3
  resource_arn       = aws_subnet.platforms[count.index].arn
  resource_share_arn = aws_ram_resource_share.share.id
}

resource "aws_ram_resource_association" "priv-dynamic-share" {
  count              = var.custom_subnets == null ? 3 : 0
  resource_arn       = aws_subnet.private_dynamic[count.index].arn
  resource_share_arn = aws_ram_resource_share.share.id
}

resource "aws_ram_resource_association" "priv-static-share" {
  count              = var.custom_subnets == null ? 3 : 0
  resource_arn       = aws_subnet.private_static[count.index].arn
  resource_share_arn = aws_ram_resource_share.share.id
}

resource "aws_ram_resource_association" "priv-rds-share" {
  count              = var.custom_subnets == null ? 3 : 0
  resource_arn       = aws_subnet.rds[count.index].arn
  resource_share_arn = aws_ram_resource_share.share.id
}

###############
#Sharing Resource share
################

resource "aws_ram_principal_association" "vpc-share" {
  for_each = var.share_principals

  principal          = each.value
  resource_share_arn = aws_ram_resource_share.share.arn
}

###############
#Creating custom subnets resource share
################

resource "aws_ram_resource_association" "custom-subnets-share" {
  for_each           = local.custom_subnets
  resource_arn       = aws_subnet.custom[each.key].arn
  resource_share_arn = aws_ram_resource_share.share.arn
}
