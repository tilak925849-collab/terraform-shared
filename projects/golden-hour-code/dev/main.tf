terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
  }

  # Partial config: bucket, key and region are passed by the pipeline with
  # -backend-config so every stack shares one bucket with a key per path.
  backend "s3" {
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region

  # Refuse to touch any account other than the one this stack belongs to.
  allowed_account_ids = [var.aws_account_id]

  default_tags {
    tags = local.tags
  }
}

locals {
  name = "${var.project}-${var.environment}"

  tags = merge(var.tags, {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
    Stack       = "projects/${var.project}/${var.environment}"
  })
}

module "ec2" {
  # Pinned to a commit: tag the modules repo (e.g. v1.0.0) and switch to ?ref=v1.0.0.
  source = "git::https://github.com/tilak925849-collab/aws-terraform-modules.git//modules/ec2?ref=2958f0b59c6e055139ea3152e07ec189b76ad6e2"

  name                        = local.name
  vpc_id                      = var.vpc_id
  subnet_ids                  = var.subnet_ids
  instance_type               = var.instance_type
  instance_count              = var.instance_count
  associate_public_ip_address = var.associate_public_ip_address
  root_volume_size            = var.root_volume_size
  ingress_rules               = var.ingress_rules

  tags = local.tags
}

output "instance_ids" {
  value = module.ec2.instance_ids
}

output "private_ips" {
  value = module.ec2.private_ips
}

output "security_group_id" {
  value = module.ec2.security_group_id
}
