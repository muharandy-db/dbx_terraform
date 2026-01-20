# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Terraform configuration for deploying a Databricks workspace on AWS with a custom VPC setup. The infrastructure provisions cross-account IAM roles, networking components, S3 storage, and the Databricks workspace itself.

## Common Commands

### Terraform Workflow
- `terraform init` - Initialize Terraform and download required providers (Databricks and AWS)
- `terraform plan` - Preview infrastructure changes
- `terraform apply` - Apply infrastructure changes
- `terraform destroy` - Tear down all provisioned infrastructure
- `terraform validate` - Validate Terraform configuration syntax
- `terraform fmt` - Format Terraform files to canonical style

### AWS CLI
The project uses AWS profile `databricks-sandbox-admin-332745928618` (see providers.tf:15)

## Architecture

### High-Level Components

1. **Cross-Account IAM Setup** (main.tf:1-29)
   - Creates IAM role for Databricks to assume
   - Uses Databricks-provided assume role and cross-account policies
   - Registers credentials with Databricks MWS API

2. **VPC and Network Configuration** (main.tf:35-64)
   - Uses `terraform-aws-modules/vpc/aws` module (v6.0.0)
   - Single NAT gateway configuration for cost optimization
   - CIDR block automatically subdivided: public subnet (1/8), two private subnets (2/8, 3/8)
   - Default security group allows all internal traffic and egress to internet

3. **VPC Endpoints** (main.tf:66-103)
   - S3 Gateway endpoint (attached to both public and private route tables)
   - STS and Kinesis-Streams interface endpoints (private subnets only)
   - Required for Databricks secure connectivity

4. **S3 Root Storage** (main.tf:115-165)
   - Workspace root bucket with encryption (AES256)
   - Public access completely blocked
   - Databricks bucket policy applied for workspace access
   - Versioning disabled

5. **Databricks Workspace** (main.tf:169-178)
   - Deployed via `databricks_mws_workspaces` resource
   - Links together credentials, storage, and network configurations

### Provider Configuration

The project uses two Databricks provider instances (providers.tf):
- `databricks.mws` - For account-level operations (workspace creation, network/storage registration)
- Default provider would be for workspace-level operations (not currently used)

### Variables and Naming

- `local.prefix` (variables.tf:23-25) - Dynamically generated prefix using random string (format: `fm-{6 chars}`)
- All resources are tagged using `var.tags`
- Credentials are stored in `vars.auto.tfvars` (client_id, client_secret, databricks_account_id)
- Default region: `ap-southeast-3` (Jakarta)

## Important Notes

- The `vars.auto.tfvars` file contains sensitive credentials and should never be committed if using version control
- The AWS profile is hardcoded in providers.tf - modify if using different AWS account
- NAT gateway uses `single_nat_gateway = true` for cost savings (not HA)
- S3 bucket has `force_destroy = true` - will delete all objects when running terraform destroy
