# One-time setup, run locally by an admin: state bucket + GitHub OIDC roles for the pipeline.
# Uses local state on purpose (it creates the remote state bucket). Keep its tfstate somewhere safe.

terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "github_repo" {
  description = "owner/name of the repo running the pipeline, e.g. tilak925849-collab/terraform-shared."
  type        = string
}

variable "state_bucket_name" {
  description = "Globally unique name for the Terraform state bucket."
  type        = string
}

variable "environments" {
  description = "GitHub environment names allowed to apply (must match projects/<project>/<env>)."
  type        = list(string)
  default     = ["dev"]
}

data "aws_caller_identity" "current" {}

# ---------- State bucket ----------

resource "aws_s3_bucket" "state" {
  bucket = var.state_bucket_name

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------- GitHub OIDC ----------

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_policy_document" "plan_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    # Plan runs on PRs and on main (no environment on the plan job).
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_repo}:pull_request",
        "repo:${var.github_repo}:ref:refs/heads/*",
      ]
    }
  }
}

data "aws_iam_policy_document" "apply_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    # Only jobs running in an approved GitHub environment can apply.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [for e in var.environments : "repo:${var.github_repo}:environment:${e}"]
    }
  }
}

# ---------- Plan role: read-only + state lock files ----------

resource "aws_iam_role" "plan" {
  name               = "github-terraform-plan"
  assume_role_policy = data.aws_iam_policy_document.plan_trust.json
}

resource "aws_iam_role_policy_attachment" "plan_readonly" {
  role       = aws_iam_role.plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

data "aws_iam_policy_document" "plan_lock" {
  statement {
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.state.arn}/*.tflock"]
  }
}

resource "aws_iam_role_policy" "plan_lock" {
  name   = "state-lock"
  role   = aws_iam_role.plan.id
  policy = data.aws_iam_policy_document.plan_lock.json
}

# ---------- Apply role: PowerUser + the IAM the ec2 module needs ----------

resource "aws_iam_role" "apply" {
  name               = "github-terraform-apply"
  assume_role_policy = data.aws_iam_policy_document.apply_trust.json
}

resource "aws_iam_role_policy_attachment" "apply_poweruser" {
  role       = aws_iam_role.apply.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

data "aws_iam_policy_document" "apply_iam" {
  # The ec2 module creates "<name>-ec2" roles and instance profiles.
  statement {
    actions = [
      "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:UpdateAssumeRolePolicy",
      "iam:TagRole", "iam:UntagRole", "iam:ListRolePolicies", "iam:ListAttachedRolePolicies",
      "iam:AttachRolePolicy", "iam:DetachRolePolicy", "iam:ListInstanceProfilesForRole",
      "iam:PassRole",
      "iam:CreateInstanceProfile", "iam:DeleteInstanceProfile", "iam:GetInstanceProfile",
      "iam:AddRoleToInstanceProfile", "iam:RemoveRoleFromInstanceProfile",
      "iam:TagInstanceProfile", "iam:UntagInstanceProfile",
    ]
    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/*-ec2",
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:instance-profile/*-ec2",
    ]
  }
}

resource "aws_iam_role_policy" "apply_iam" {
  name   = "ec2-module-iam"
  role   = aws_iam_role.apply.id
  policy = data.aws_iam_policy_document.apply_iam.json
}

# ---------- Values to put into GitHub repo / environment variables ----------

output "TF_STATE_BUCKET" {
  value = aws_s3_bucket.state.bucket
}

output "AWS_PLAN_ROLE_ARN" {
  value = aws_iam_role.plan.arn
}

output "AWS_APPLY_ROLE_ARN" {
  value = aws_iam_role.apply.arn
}

# ---------- Jenkins role (Jenkinsfile assumes this via ci/aws-auth.sh) ----------

variable "jenkins_principal_arns" {
  description = "IAM principals Jenkins runs as (agent instance role or IAM user). Empty = no Jenkins role."
  type        = list(string)
  default     = []
}

data "aws_iam_policy_document" "jenkins_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = var.jenkins_principal_arns
    }
  }
}

resource "aws_iam_role" "jenkins" {
  count                = length(var.jenkins_principal_arns) > 0 ? 1 : 0
  name                 = "jenkins-terraform-dev"
  assume_role_policy   = data.aws_iam_policy_document.jenkins_trust.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "jenkins_poweruser" {
  count      = length(aws_iam_role.jenkins)
  role       = aws_iam_role.jenkins[0].name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

resource "aws_iam_role_policy" "jenkins_iam" {
  count  = length(aws_iam_role.jenkins)
  name   = "ec2-module-iam"
  role   = aws_iam_role.jenkins[0].id
  policy = data.aws_iam_policy_document.apply_iam.json
}

output "JENKINS_ROLE_ARN" {
  value = try(aws_iam_role.jenkins[0].arn, null)
}
