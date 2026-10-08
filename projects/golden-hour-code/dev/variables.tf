variable "aws_region" {
  description = "AWS region for this stack."
  type        = string
}

variable "aws_account_id" {
  description = "AWS account this stack deploys to. Terraform fails if credentials point elsewhere."
  type        = string
}

variable "project" {
  description = "Project name, used in resource names and tags."
  type        = string
}

variable "environment" {
  description = "Environment name (dev, stage, prod)."
  type        = string
}

variable "vpc_id" {
  description = "Existing VPC to launch into."
  type        = string
}

variable "subnet_ids" {
  description = "Existing subnets to launch into."
  type        = list(string)
}

variable "instance_type" {
  description = "EC2 instance type."
  type        = string
  default     = "t3.micro"
}

variable "instance_count" {
  description = "Number of standalone instances."
  type        = number
  default     = 1
}

variable "associate_public_ip_address" {
  description = "Give instances a public IP (only for public subnets)."
  type        = bool
  default     = false
}

variable "root_volume_size" {
  description = "Root EBS volume size in GiB."
  type        = number
  default     = 20
}

variable "ingress_rules" {
  description = "Security group ingress rules, passed through to the ec2 module."
  type = list(object({
    description              = optional(string, "")
    from_port                = number
    to_port                  = number
    protocol                 = optional(string, "tcp")
    cidr_ipv4                = optional(string)
    source_security_group_id = optional(string)
  }))
  default = []
}

variable "tags" {
  description = "Extra tags for all resources."
  type        = map(string)
  default     = {}
}
