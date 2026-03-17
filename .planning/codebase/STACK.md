# Technology Stack

**Analysis Date:** 2026-03-17

## Languages

**Primary:**
- HCL (HashiCorp Configuration Language) - All infrastructure definitions (`*.tf` files)

**Secondary:**
- Bash - Setup scripts (`setup/setup-dynamodb-lock.sh`)
- JSON - IAM policy definitions (`setup/interview-candidate-policy.json`)

## Runtime

**Environment:**
- Terraform >= 1.0 (required version constraint in `main.tf` line 2)
- OpenTofu (compatible drop-in replacement; README references `tofu` commands)

**Package Manager:**
- Terraform/OpenTofu built-in provider registry
- No lockfile committed (`.terraform.lock.hcl` is gitignored in `.gitignore` line 6)

## Frameworks

**Core:**
- Terraform/OpenTofu >= 1.0 - Infrastructure as Code engine

**Modules:**
- `cloudposse/label/null` v0.25.0 - Resource naming and tagging convention system (used in `context.tf` line 24)

**Testing:**
- Not detected - No test framework or test files present

**Build/Dev:**
- AWS CLI - Used in setup scripts for DynamoDB table creation (`setup/setup-dynamodb-lock.sh`)

## Key Dependencies

**Terraform Providers:**
- `hashicorp/aws` ~> 5.0 - AWS resource provisioning (`main.tf` lines 5-8)
- `hashicorp/null` ~> 3.0 - Null resources for labeling module (`main.tf` lines 9-12)

**Modules:**
- `cloudposse/label/null` v0.25.0 - Standardized naming/tagging for all AWS resources (`context.tf` lines 23-46). Provides `module.this.id` for resource names and `module.this.tags` for consistent tagging.

## Configuration

**Environment:**
- AWS credentials via environment variables (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_DEFAULT_REGION`)
- No `.env` files - credentials are set in shell environment per `README.md` lines 190-196
- `terraform.tfvars` contains non-secret configuration (gitignored but present in repo for interview context)

**Variables (in `variables.tf` and `context.tf`):**
- `aws_region` - AWS region, defaults to `eu-west-1`
- `vpc_cidr` - CIDR block for VPC (required, no default)
- `availability_zones` - List of AZs, defaults to `["eu-west-1a", "eu-west-1b", "eu-west-1c"]`
- CloudPosse context variables: `namespace`, `environment`, `stage`, `name`, `tags`, etc.

**Current values (in `terraform.tfvars`):**
- `namespace = "dna"`
- `environment = "interview"`
- `name = "ecs"`
- `vpc_cidr = "10.64.0.0/20"`
- `aws_region = "eu-west-1"`

**State Backend:**
- S3 bucket: `dna-stag-terraform-state` with key `interview/terraform.tfstate` (`main.tf` lines 15-21)
- DynamoDB locking table: `dna-stag-terraform-locks`
- Encryption enabled
- Region: `eu-west-1`

**Build:**
- `main.tf` - Provider and backend configuration
- `context.tf` - CloudPosse naming/labeling module (copy from `cloudposse/terraform-null-label`)
- `variables.tf` - All variable declarations (272 lines, most from context.tf pattern)
- `terraform.tfvars` - Variable values for this deployment

## Platform Requirements

**Development:**
- Terraform >= 1.0 or OpenTofu (README uses `tofu` commands)
- AWS CLI (for setup scripts and credential management)
- AWS account access with appropriate IAM permissions (defined in `setup/interview-candidate-policy.json`)
- Shell environment (Bash) for setup scripts

**Production:**
- AWS account ID: `105458107979`
- Region: `eu-west-1` (Ireland)
- Pre-existing S3 bucket for state: `dna-stag-terraform-state`
- Pre-existing DynamoDB table for locking: `dna-stag-terraform-locks`

## Project Nature

This is an **interview exercise infrastructure scaffold**. The base code provides VPC, subnets, route tables, internet gateway, and ECS IAM roles. Candidates are expected to incrementally add:
1. **Exercise 1:** ECS Cluster + ALB + ECS Service (Fargate) running `hashicorp/http-echo:latest`
2. **Exercise 2:** RDS PostgreSQL + pgweb container (`sosedoff/pgweb:latest`)
3. **Exercise 3:** Route53 + ACM certificate for HTTPS

---

*Stack analysis: 2026-03-17*
