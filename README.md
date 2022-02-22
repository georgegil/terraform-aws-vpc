# terraform-aws-vpc

## Example Usage

```hcl
module "aws-vpc" {
  source = "github.com/georgegil/terraform-aws-vpc.git?ref=<current version>"

  tags = {
    "Tag_1" = "Value_1"
    "Tag_2" = "Value_2"
    "Tag_3" = "Value_3"
  }

  domain_name         = ["gglabs.co.uk"]
  dns_server          = ["10.120.4.20", "10.121.4.20"]
  vpc_cidr            = "10.126.0.0/20"
  subnet_size         = "25"
  use_infosec_subnet  = false
  amazon_side_asn_tgw = 420002001
  amazon_side_asn_dcg = 420002002
  use_static_routing  = false
  vpc_prefix          = "K8SPROJECT"

  custom_subnets = {
    "K8SC" = {
      "cidr" = "10.120.4.0/22"
      "az"   = "eu-west-2c"
    }
    "K8SA" = {
      cidr = "10.120.8.0/22"
      "az" = "eu-west-2a"
    }
    "K8SB" = {
      cidr = "10.120.12.0/22"
      "az" = "eu-west-2b"
    }
  }

  share_principals = {
    mba   = "445125883366"
    example_ou = "ou-123-4567890"
  }
}
```

where `<current version>` is the most recent release.

## Related Links


## Development

Feel free to create a branch and submit a pull request to make changes to the module.