variable "tags" {
  description = "Please reference the current tagging policy for required tags and allowed values.  See README for link to policy."
  type        = map(string)
}

variable "domain_name" {
  description = "List of private DNS domains that needs to be resolved from within the VPC. If `domain_search_suffix` is not defined, then the first domain specified in this variable will be selected for DNS search suffix"
  type        = list(string)
}

variable "domain_search_suffix" {
  description = "The domain that should be the DNS search suffix of the VPC as per RFC3397. Leaving this null will select the first domain in `domain_name` variable."
  type        = string
  default     = null
}

variable "dns_servers" {
  description = "DNS servers of the VPC."
  type        = list(string)
}

variable "vpc_cidr" {
  description = "The subnet of the VPC. Example value '192.168.0.0/16' (must be at least /20 subnet)."
  type        = string
}

variable "subnet_size" {
  description = "The size of each subnet in bits."
  type        = number
  default     = "25"
}


variable "amazon_side_asn_tgw" {
  description = "Private Autonomous System Number (ASN) for the Amazon side of a BGP session. The range is '64512' to '65534' for 16-bit ASNs and '4200000000' to '4294967294' for 32-bit ASNs. Required when creating a Transit Gateway by not specyfying a value for 'tgw_id'."
  type        = number
  default     = null
}

variable "amazon_side_asn_dcg" {
  description = "The ASN to be configured on the Amazon side of the connection. The ASN must be in the private range of '64512' to '65534' or '4200000000' to '4294967294'. Required when creating a Direct Connect Gateway by not specyfying a value for 'tgw_id'."
  type        = number
  default     = null
}

variable "dx_gateway_cidr" {
  description = "The CIDR that the Direct Connect Gateway advertises to the on-premise routers through BGP. Required when creating a Direct Connect Gateway by not specyfying a value for 'tgw_id'."
  type        = list(string)
  default     = null
}

variable "tgw_id" {
  description = "The Direct Connect Gateway name if needing to link a Transit Gateway to a remote Direct Connect Gateway in a different region."
  type        = string
  default     = null
}

variable "remote_dx_gateway_name" {
  description = "Transit Gateway ID when linking VPC to an existing Transit Gateway. This value is required when not specifying 'amazon_side_asn_tgw', 'amazon_side_asn_dcg', 'dx_gateway_cidr', 'remote_dx_gateway_name' as this will not create a Direct Connect Gateway."
  type        = list(string)
  default     = null
}

variable "use_static_routing" {
  description = "Disables static routing when using BGP ingested routes to the Transit Gateway. Cannot be used in conjuction with 'tgw_id'."
  type        = bool
  default     = false
}

variable "custom_subnets" {
  description = "Provisions dedicated subnet for RDS Resources."
  type        = map(any)
  default     = null
}

variable "vpc_prefix" {
  description = "The VPC name prefix when creating a non standard VPC"
  type        = string
  default     = null
}

variable "share_principals" {
  description = "Principals this VPC and subnets should be shared with.  This can be either an account ID or OU arn."
  type        = map(string)
}
