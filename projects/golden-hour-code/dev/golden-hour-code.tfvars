aws_account_id = "629807611256"
aws_region     = "us-east-1"
project        = "golden-hour-code"
environment    = "dev"

# Replace with your existing VPC and private subnets.
vpc_id     = "vpc-xxxxxxxxxxxxxxxxx"
subnet_ids = ["subnet-xxxxxxxxxxxxxxxxx", "subnet-yyyyyyyyyyyyyyyyy"]

instance_type  = "t3.micro"
instance_count = 1

# Access is via SSM Session Manager, so no SSH ingress is needed.
ingress_rules = []

tags = {
  Owner      = "platform-team"
  CostCenter = "golden-hour-code"
}
