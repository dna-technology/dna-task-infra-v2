# Architecture

**Analysis Date:** 2026-03-17

## Pattern Overview

**Overall:** Flat Terraform root module with resource-domain file splitting

**Key Characteristics:**
- Single Terraform root module (no child modules beyond `cloudposse/label/null`)
- Resources organized by AWS service domain into separate `.tf` files
- Remote S3 backend with DynamoDB state locking
- CloudPosse `terraform-null-label` for consistent naming/tagging via `context.tf`
- Interview exercise scaffold: base networking + IAM pre-built, candidate extends with ECS/ALB/RDS/Route53

## Layers

**Provider & Backend (Configuration Layer):**
- Purpose: Defines Terraform version constraints, required providers, remote state backend, and AWS provider config
- Location: `main.tf`
- Contains: `terraform {}` block (backend, required_providers), `provider "aws"` block
- Depends on: S3 bucket `dna-stag-terraform-state` and DynamoDB table `dna-stag-terraform-locks` (pre-existing)
- Used by: All resource files

**Naming & Tagging (Context Layer):**
- Purpose: Provides consistent resource naming (`module.this.id`) and tagging (`module.this.tags`) across all resources
- Location: `context.tf`
- Contains: `module "this"` (cloudposse/label/null v0.25.0) + all context variables (namespace, environment, stage, name, etc.)
- Depends on: `terraform.tfvars` for input values
- Used by: Every resource file that creates AWS resources — all use `module.this.id` for names and `module.this.tags` for tags

**Networking Layer:**
- Purpose: Creates the VPC, subnets (public + private), internet gateway, and route tables
- Location: `vpc.tf`
- Contains: `aws_vpc.main`, `aws_internet_gateway.main`, `aws_subnet.public[*]`, `aws_subnet.private[*]`, `aws_route_table.public`, `aws_route_table_association.public[*]`
- Depends on: `var.vpc_cidr`, `var.availability_zones`, context layer for naming
- Used by: Future ECS services (private subnets), ALB (public subnets), RDS (private subnets)

**IAM Layer:**
- Purpose: Creates ECS task execution and task roles with appropriate assume-role policies
- Location: `iam-ecs.tf`
- Contains: `aws_iam_role.ecs_task_execution`, `aws_iam_role_policy_attachment.ecs_task_execution`, `aws_iam_role.ecs_task`
- Depends on: Context layer for naming/tagging
- Used by: Future ECS task definitions (task execution role for pulling images/logging, task role for application permissions)

**Input Layer:**
- Purpose: Defines all configurable variables with types, defaults, and descriptions
- Location: `variables.tf` (custom vars), `context.tf` (context/label vars)
- Contains: `var.aws_region`, `var.vpc_cidr`, `var.availability_zones` plus ~20 context variables
- Depends on: `terraform.tfvars` for values
- Used by: All resource files

**Output Layer:**
- Purpose: Exposes key resource identifiers for downstream use
- Location: `outputs.tf`
- Contains: `vpc_id`, `public_subnet_ids`, `private_subnet_ids`
- Depends on: Networking layer resources
- Used by: Consumers of `tofu output` (candidates during exercises, downstream modules)

## Data Flow

**Terraform Apply Flow:**

1. Terraform reads `main.tf` — initializes S3 backend, loads state from `s3://dna-stag-terraform-state/interview/terraform.tfstate`
2. Variables loaded from `variables.tf` defaults + `terraform.tfvars` overrides
3. `module.this` in `context.tf` computes naming context (`dna-interview-ecs`) and tags
4. Resource files (`vpc.tf`, `iam-ecs.tf`) reference `module.this.id` and `module.this.tags` for consistent naming
5. Resources created/updated in AWS `eu-west-1`
6. Outputs written to state and displayed

**Naming Flow:**

1. `terraform.tfvars` sets `namespace = "dna"`, `environment = "interview"`, `name = "ecs"`
2. `module.this` (cloudposse/label/null) computes `id = "dna-interview-ecs"`
3. Resources use `"${module.this.id}-<suffix>"` pattern (e.g., `dna-interview-ecs-vpc`)
4. Tags automatically include namespace, environment, name labels

**State Management:**
- Remote state stored in S3 with encryption enabled
- DynamoDB table provides state locking to prevent concurrent modifications
- State key: `interview/terraform.tfstate`

## Key Abstractions

**CloudPosse Null Label (`module.this`):**
- Purpose: Single source of truth for resource naming and tagging conventions
- Location: `context.tf` (module declaration + all variable definitions)
- Pattern: Every AWS resource references `module.this.id` for its name and `module.this.tags` (merged with resource-specific Name tag) for tags
- Example usage:
  ```hcl
  tags = merge(
    module.this.tags,
    { Name = "${module.this.id}-vpc" }
  )
  ```

**Count-based Multi-AZ Resources:**
- Purpose: Create one resource per availability zone without duplication
- Examples: `aws_subnet.public[*]` and `aws_subnet.private[*]` in `vpc.tf`
- Pattern: `count = length(var.availability_zones)` with `cidrsubnet()` for CIDR calculation

## Entry Points

**Terraform CLI (primary entry point):**
- Location: Project root (all `.tf` files in `/`)
- Triggers: `tofu init`, `tofu plan`, `tofu apply`, `tofu destroy`
- Responsibilities: Provisions/manages all AWS infrastructure defined in `.tf` files

**Setup Scripts:**
- Location: `setup/`
- Contains: `setup/interview-candidate-policy.json` — IAM policy for interview candidates
- Purpose: Pre-interview setup by interviewers (not part of Terraform execution)

## Error Handling

**Strategy:** Terraform's built-in plan/apply cycle with state locking

**Patterns:**
- DynamoDB-based state locking prevents concurrent modifications (`main.tf` backend config)
- IAM policy in `setup/interview-candidate-policy.json` includes `DenyDangerousActions` statement to prevent destructive operations (e.g., creating/deleting IAM users/roles, running EC2 instances, deleting S3 buckets)
- Region restriction: `DenyOtherRegions` statement blocks operations outside `eu-west-1`
- Variable validation: `context.tf` includes validation blocks for `label_key_case` and `label_value_case`

## Cross-Cutting Concerns

**Naming:** All resources use `module.this.id` prefix from CloudPosse null-label (`context.tf`). Pattern: `"${module.this.id}-<resource-type>"`. Current prefix: `dna-interview-ecs`.

**Tagging:** All resources merge `module.this.tags` with resource-specific `Name` tag. The `provider "aws"` block in `main.tf` also sets `default_tags` from `module.this.tags`, providing a safety net.

**Security:** IAM candidate policy restricts to `eu-west-1`, denies dangerous actions. ECS roles follow least-privilege with separate task execution role (for AWS API calls like ECR pull, CloudWatch logs) and task role (for application-level permissions).

**Logging:** Not yet configured. The README references CloudWatch log group `/aws/ecs/dna-interview-ecs` as expected for Exercise 1.

**Validation:** Terraform-native variable validation in `context.tf` for label case values. No external validation tools (tfsec, checkov) configured, though `STEERING.md` recommends them.

## Exercise Architecture (Candidate Extensions)

The codebase is a scaffold for 3 progressive exercises. Each exercise adds new `.tf` files:

**Exercise 1 — ECS + ALB (new files to create):**
- ECS Cluster (Fargate), Task Definition (`hashicorp/http-echo`), Service
- Application Load Balancer in public subnets
- Security groups (ALB: HTTP from internet; ECS: traffic from ALB only)
- Target group with health checks (target type: IP for Fargate)

**Exercise 2 — RDS + pgweb (extends Exercise 1):**
- RDS PostgreSQL 16.6 instance in private subnets (`db.t4g.micro`)
- DB subnet group across all AZs
- RDS security group (port 5432 from ECS SG only)
- Updated ECS task: `sosedoff/pgweb` with connection string

**Exercise 3 — Route53 + HTTPS (extends Exercise 2):**
- Route53 hosted zone + A record alias to ALB
- ACM certificate with DNS validation
- HTTPS listener on ALB (port 443) with TLS 1.3 policy
- Optional HTTP-to-HTTPS redirect

---

*Architecture analysis: 2026-03-17*
