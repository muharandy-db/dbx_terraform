# Databricks Workspace Deployment on AWS

This Terraform project automates the deployment of a Databricks workspace on AWS with a custom VPC configuration.

## Prerequisites

1. **AWS Account** with administrative access
2. **Databricks Account** (E2 or Premium tier)
3. **Terraform** installed (v1.0+)
4. **AWS CLI** installed and configured
5. **Databricks Service Principal** credentials (client_id and client_secret)

## Architecture Overview

This deployment creates:
- Cross-account IAM role for Databricks
- VPC with public and private subnets
- VPC endpoints for S3, STS, and Kinesis
- S3 bucket for workspace root storage
- Databricks workspace connected to the infrastructure

## Setup Instructions

### Step 1: Configure AWS Credentials

Set up AWS CLI with a named profile:

```bash
aws configure --profile <your-profile-name>
```

Update `providers.tf` line 15 with your AWS profile name:

```hcl
provider "aws" {
  region  = var.region
  profile = "<your-profile-name>"  # Replace with your AWS profile
}
```

### Step 2: Create Databricks Service Principal

1. Log in to your Databricks account console at https://accounts.cloud.databricks.com
2. Navigate to **User management** > **Service principals**
3. Click **Add service principal**
4. Note the **Client ID** (Application ID)
5. Generate a **Client Secret** in the "Credentials & secrets" tab and save it securely
6. Grant the service principal **Account Admin** role

### Step 3: Get Databricks Account ID

1. In the Databricks account console, click on your username in the top-right
2. The **Account ID** is displayed in the dropdown menu
3. Copy this ID for the next step

### Step 4: Configure Variables

Create or update `vars.auto.tfvars` with your credentials:

```hcl
# Databricks Service Principal credentials
client_id                = "<your-client-id>"
client_secret            = "<your-client-secret>"
databricks_account_id    = "<your-account-id>"

# AWS Region
region = "ap-southeast-3"  # Change to your preferred region

# Resource tags
tags = {
  Owner       = "<your-email@company.com>"
  Environment = "<Development/Production/Test>"
  Budget      = "<your-budget-code>"
}
```

**⚠️ IMPORTANT**: Never commit `vars.auto.tfvars` to version control! Add it to `.gitignore`:

```bash
echo "vars.auto.tfvars" >> .gitignore
echo "*.tfvars" >> .gitignore
```

### Step 5: Initialize Terraform

```bash
terraform init
```

This downloads the required providers:
- Databricks provider
- AWS provider
- terraform-aws-modules/vpc

### Step 6: Review the Plan

```bash
terraform plan
```

Review the planned infrastructure changes. You should see:
- ~25-30 resources to be created
- IAM roles and policies
- VPC with subnets, NAT gateway, and Internet gateway
- VPC endpoints
- S3 bucket with encryption and policies
- Databricks workspace

### Step 7: Deploy Infrastructure

```bash
terraform apply
```

Type `yes` when prompted. The deployment takes approximately 10-15 minutes.

### Step 8: Access Your Workspace

After successful deployment, Terraform outputs the workspace URL:

```
databricks_host = "https://xxxxx.cloud.databricks.com"
```

Access this URL using your Databricks account credentials.

## Configuration Options

### Customizing Network CIDR

Edit `variables.tf` or override in `vars.auto.tfvars`:

```hcl
cidr_block = "10.4.0.0/16"  # Change to your preferred CIDR range
```

The CIDR block is automatically subdivided:
- Public subnet: /19 (first subnet)
- Private subnet 1: /19 (second subnet)
- Private subnet 2: /19 (third subnet)

### Changing AWS Region

Update the `region` variable in `vars.auto.tfvars`:

```hcl
region = "us-east-1"  # or your preferred region
```

**Note**: Ensure the region supports Databricks E2 deployment.

### Resource Naming

Resources are automatically prefixed with `fm-{random-6-chars}` (defined in `variables.tf`). To customize the prefix pattern, modify the `locals.prefix` value in `variables.tf`:

```hcl
locals {
  prefix = "mycompany-${random_string.naming.result}"
}
```

## Cost Optimization Notes

This configuration uses:
- **Single NAT Gateway** (`single_nat_gateway = true`) to reduce costs
  - For high availability, set `single_nat_gateway = false` (adds cost)
- **S3 Standard storage** for root bucket
- **Interface VPC endpoints** for STS and Kinesis (charged per hour)

## Cleanup

To destroy all infrastructure:

```bash
terraform destroy
```

Type `yes` when prompted. This will:
- Delete the Databricks workspace
- Remove all AWS infrastructure
- Delete the S3 bucket and all contents (due to `force_destroy = true`)

**⚠️ WARNING**: This is irreversible. Ensure you have backups of any important data.

## Troubleshooting

### Authentication Errors

**Error**: "Invalid client credentials"
- Verify your `client_id` and `client_secret` are correct
- Ensure the service principal has Account Admin role
- Check that credentials haven't expired

### VPC Endpoint Errors

**Error**: "VPC endpoint not available in region"
- Some regions may not support all VPC endpoints
- Check AWS service availability in your region
- Remove unsupported endpoints from `main.tf` lines 73-100

### S3 Bucket Already Exists

**Error**: "BucketAlreadyExists"
- S3 bucket names must be globally unique
- The random string ensures uniqueness, but conflicts can occur
- Run `terraform destroy` and `terraform apply` again to generate a new name

### Cross-Account Role Issues

**Error**: "Error assuming role"
- Ensure your Databricks account ID is correct
- Verify the AWS account has permissions to create IAM roles
- Check that the Databricks account is active and in good standing

## Security Best Practices

1. **Never commit credentials** to version control
2. **Use separate accounts** for development and production
3. **Enable AWS CloudTrail** for audit logging
4. **Restrict IAM permissions** to least privilege
5. **Enable MFA** on both AWS and Databricks accounts
6. **Rotate credentials** regularly (service principal secrets)
7. **Use AWS Secrets Manager** or HashiCorp Vault for credential management in production

## File Structure

```
.
├── main.tf              # Main infrastructure definitions
├── providers.tf         # Provider configurations
├── variables.tf         # Variable declarations and defaults
├── vars.auto.tfvars     # Sensitive credentials (DO NOT COMMIT)
├── CLAUDE.md           # Developer guidance for Claude Code
└── README.md           # This file
```

## Additional Resources

- [Databricks AWS Deployment Guide](https://docs.databricks.com/en/administration-guide/cloud-configurations/aws/index.html)
- [Terraform AWS VPC Module](https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws/latest)
- [Databricks Terraform Provider](https://registry.terraform.io/providers/databricks/databricks/latest/docs)

## Support

For issues with:
- **Terraform configuration**: Review Terraform and provider documentation
- **Databricks account setup**: Contact Databricks support
- **AWS infrastructure**: Check AWS service health and documentation
