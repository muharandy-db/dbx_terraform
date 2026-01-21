data "databricks_aws_assume_role_policy" "this" {
  provider    = databricks.mws
  external_id = var.databricks_account_id
}

resource "aws_iam_role" "cross_account_role" {
  name               = "${local.prefix}-crossaccount"
  assume_role_policy = data.databricks_aws_assume_role_policy.this.json
  tags               = var.tags
}

data "databricks_aws_crossaccount_policy" "this" {
  provider    = databricks.mws
  policy_type = "customer"
}

resource "aws_iam_role_policy" "this" {
  name   = "${local.prefix}-policy"
  role   = aws_iam_role.cross_account_role.id
  policy = data.databricks_aws_crossaccount_policy.this.json
}

resource "databricks_mws_credentials" "this" {
  provider         = databricks.mws
  role_arn         = aws_iam_role.cross_account_role.arn
  credentials_name = "${local.prefix}-creds"
  depends_on       = [aws_iam_role_policy.this]
}

data "aws_availability_zones" "available" {}

## VPC Setup

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.0.0"

  name = local.prefix
  cidr = var.cidr_block
  azs  = data.aws_availability_zones.available.names
  tags = var.tags

  enable_dns_hostnames = true
  enable_nat_gateway   = true
  single_nat_gateway   = true
  create_igw           = true

  public_subnets = [cidrsubnet(var.cidr_block, 3, 0)]
  private_subnets = [cidrsubnet(var.cidr_block, 3, 1),
  cidrsubnet(var.cidr_block, 3, 2)]

  manage_default_security_group = true
  default_security_group_name   = "${local.prefix}-sg"

  default_security_group_egress = [{
    cidr_blocks = "0.0.0.0/0"
  }]

  default_security_group_ingress = [{
    description = "Allow all internal TCP and UDP"
    self        = true
  }]
}

module "vpc_endpoints" {
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "6.0.0"

  vpc_id             = module.vpc.vpc_id
  security_group_ids = [module.vpc.default_security_group_id]

  endpoints = {
    s3 = {
      service      = "s3"
      service_type = "Gateway"
      route_table_ids = flatten([
        module.vpc.private_route_table_ids,
      module.vpc.public_route_table_ids])
      tags = {
        Name = "${local.prefix}-s3-vpc-endpoint"
      }
    },
    sts = {
      service             = "sts"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnets
      tags = {
        Name = "${local.prefix}-sts-vpc-endpoint"
      }
    },
    kinesis-streams = {
      service             = "kinesis-streams"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnets
      tags = {
        Name = "${local.prefix}-kinesis-vpc-endpoint"
      }
    },
  }

  tags = var.tags
}

resource "databricks_mws_networks" "this" {
  provider           = databricks.mws
  account_id         = var.databricks_account_id
  network_name       = "${local.prefix}-network"
  security_group_ids = [module.vpc.default_security_group_id]
  subnet_ids         = module.vpc.private_subnets
  vpc_id             = module.vpc.vpc_id
}

## Root bucket setup 
resource "aws_s3_bucket" "root_storage_bucket" {
  bucket        = "${local.prefix}-rootbucket"
  acl           = "private"
  force_destroy = true
  tags = merge(var.tags, {
    Name = "${local.prefix}-rootbucket"
  })
}

resource "aws_s3_bucket_server_side_encryption_configuration" "root_storage_bucket" {
  bucket = aws_s3_bucket.root_storage_bucket.bucket

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "root_storage_bucket" {
  bucket                  = aws_s3_bucket.root_storage_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
  depends_on              = [aws_s3_bucket.root_storage_bucket]
}

data "databricks_aws_bucket_policy" "this" {
  bucket = aws_s3_bucket.root_storage_bucket.bucket
}

resource "aws_s3_bucket_policy" "root_bucket_policy" {
  bucket     = aws_s3_bucket.root_storage_bucket.id
  policy     = data.databricks_aws_bucket_policy.this.json
  depends_on = [aws_s3_bucket_public_access_block.root_storage_bucket]
}

resource "aws_s3_bucket_versioning" "root_bucket_versioning" {
  bucket = aws_s3_bucket.root_storage_bucket.id
  versioning_configuration {
    status = "Disabled"
  }
}

resource "databricks_mws_storage_configurations" "this" {
  provider                   = databricks.mws
  account_id                 = var.databricks_account_id
  bucket_name                = aws_s3_bucket.root_storage_bucket.bucket
  storage_configuration_name = "${local.prefix}-storage"
}

# Workspace Deployment

resource "databricks_mws_workspaces" "this" {
  provider       = databricks.mws
  account_id     = var.databricks_account_id
  aws_region     = var.region
  workspace_name = local.prefix

  credentials_id           = databricks_mws_credentials.this.credentials_id
  storage_configuration_id = databricks_mws_storage_configurations.this.storage_configuration_id
  network_id               = databricks_mws_networks.this.network_id
}

output "databricks_host" {
  value = databricks_mws_workspaces.this.workspace_url
}

# Unity Catalog Storage Setup

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "unity_catalog" {
  bucket        = "${local.prefix}-unity-catalog"
  force_destroy = true
  tags = merge(var.tags, {
    Name = "${local.prefix}-unity-catalog"
  })
}

resource "aws_s3_bucket_server_side_encryption_configuration" "unity_catalog" {
  bucket = aws_s3_bucket.unity_catalog.bucket

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "unity_catalog" {
  bucket                  = aws_s3_bucket.unity_catalog.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
  depends_on              = [aws_s3_bucket.unity_catalog]
}

resource "aws_s3_bucket_versioning" "unity_catalog" {
  bucket = aws_s3_bucket.unity_catalog.id
  versioning_configuration {
    status = "Disabled"
  }
}

# IAM Role for Unity Catalog - created first without self-reference
resource "aws_iam_role" "unity_catalog" {
  name = "${local.prefix}-unity-catalog-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::414351767826:role/unity-catalog-prod-UCMasterRole-14S5ZJVKOTYTL"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "sts:ExternalId" = var.databricks_account_id
          }
        }
      }
    ]
  })
  tags = var.tags

  lifecycle {
    ignore_changes = [assume_role_policy]
  }
}

# Update trust policy to add self-assuming capability (required since Jan 2025)
resource "aws_iam_role_policy" "unity_catalog_self_assume" {
  name = "${local.prefix}-unity-catalog-self-assume"
  role = aws_iam_role.unity_catalog.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "sts:AssumeRole"
        Resource = aws_iam_role.unity_catalog.arn
      }
    ]
  })
}

# Wait for IAM role to propagate before updating trust policy
resource "time_sleep" "wait_for_iam_role" {
  depends_on      = [aws_iam_role.unity_catalog]
  create_duration = "15s"
}

# Update the assume role policy after role is created to include self-reference
resource "terraform_data" "update_unity_catalog_trust_policy" {
  depends_on = [time_sleep.wait_for_iam_role]

  provisioner "local-exec" {
    command = <<-EOT
      aws iam update-assume-role-policy \
        --role-name ${aws_iam_role.unity_catalog.name} \
        --policy-document '{
          "Version": "2012-10-17",
          "Statement": [
            {
              "Effect": "Allow",
              "Principal": {
                "AWS": [
                  "arn:aws:iam::414351767826:role/unity-catalog-prod-UCMasterRole-14S5ZJVKOTYTL",
                  "${aws_iam_role.unity_catalog.arn}"
                ]
              },
              "Action": "sts:AssumeRole",
              "Condition": {
                "StringEquals": {
                  "sts:ExternalId": "${var.databricks_account_id}"
                }
              }
            }
          ]
        }' \
        --profile ${var.aws_profile}
    EOT
  }
}

resource "aws_iam_role_policy" "unity_catalog_s3" {
  name = "${local.prefix}-unity-catalog-s3-policy"
  role = aws_iam_role.unity_catalog.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:ListBucketMultipartUploads",
          "s3:ListMultipartUploadParts",
          "s3:AbortMultipartUpload"
        ]
        Resource = [
          aws_s3_bucket.unity_catalog.arn,
          "${aws_s3_bucket.unity_catalog.arn}/*"
        ]
        Effect = "Allow"
      },
      {
        Action   = ["sts:AssumeRole"]
        Resource = aws_iam_role.unity_catalog.arn
        Effect   = "Allow"
      }
    ]
  })
}

output "unity_catalog_bucket" {
  value = aws_s3_bucket.unity_catalog.bucket
}

output "unity_catalog_iam_role_arn" {
  value = aws_iam_role.unity_catalog.arn
}