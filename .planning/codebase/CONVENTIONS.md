# Coding Conventions

**Analysis Date:** 2026-03-17

## Language & Tooling

**Primary Language:** HCL (HashiCorp Configuration Language) — Terraform/OpenTofu
**Required Version:** >= 1.0 (specified in `main.tf`)
**CLI Tool:** OpenTofu (`tofu` command referenced in `README.md`)

## Naming Patterns

**Files:**
- Use lowercase kebab-case: `iam-ecs.tf`, `context.tf`, `vpc.tf`
- Group resources by domain/concern in dedicated `.tf` files (e.g., `vpc.tf` for all VPC resources, `iam-ecs.tf` for ECS-related IAM)
- Standard Terraform file naming: `main.tf`, `variables.tf`, `outputs.tf`
- Setup/utility scripts go in `setup/` directory

**Resources:**
- Use `snake_case` for Terraform resource names: `aws_vpc.main`, `aws_subnet.public`, `aws_iam_role.ecs_task_execution`
- Prefer `main` as the local name for primary/singleton resources: `aws_vpc.main`, `aws_internet_gateway.main`
- Use descriptive names for role-specific resources: `aws_iam_role.ecs_task_execution`, `aws_iam_role.ecs_task`

**AWS Resource Names (Tags):**
- ALL AWS resource names MUST use `module.this.id` prefix from `context.tf` (CloudPosse terraform-null-label)
- Pattern: `"${module.this.id}-<suffix>"` — e.g., `"${module.this.id}-vpc"`, `"${module.this.id}-ecs-task-execution"`
- This generates names like `dna-interview-ecs-vpc`, `dna-interview-ecs-ecs-task-execution`

**Variables:**
- Use `snake_case`: `aws_region`, `vpc_cidr`, `availability_zones`
- Always include `description` field
- Always include `type` constraint
- Include `default` when a sensible default exists

**Outputs:**
- Use `snake_case`: `vpc_id`, `public_subnet_ids`, `private_subnet_ids`
- Always include `description` field

## Resource Tagging Convention

**Every AWS resource** must include tags via one of these patterns:

**Pattern 1 — Tags with Name override (most resources):**
```hcl
tags = merge(
  module.this.tags,
  {
    Name = "${module.this.id}-<suffix>"
  }
)
```
See: `vpc.tf` lines 7-12, 19-24, 35-42

**Pattern 2 — Tags with additional metadata:**
```hcl
tags = merge(
  module.this.tags,
  {
    Name = "${module.this.id}-private-subnet-${count.index + 1}"
    Type = "private"
    AZ   = var.availability_zones[count.index]
  }
)
```
See: `vpc.tf` lines 52-59

**Pattern 3 — Module tags only (via provider default_tags):**
```hcl
provider "aws" {
  default_tags {
    tags = module.this.tags
  }
}
```
See: `main.tf` lines 27-29

**Context variables** are set in `terraform.tfvars`:
- `namespace = "dna"`
- `environment = "interview"`
- `name = "ecs"`

## Code Style

**Formatting:**
- Use `terraform fmt` / `tofu fmt` (standard HCL formatting)
- 2-space indentation for HCL blocks
- Align `=` signs within a block for readability (Terraform formatter convention)
- Blank line between resource arguments and nested blocks

**Attribute Alignment:**
```hcl
# Aligned equals signs within a block
resource "aws_subnet" "public" {
  count                   = length(var.availability_zones)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true
}
```
See: `vpc.tf` lines 28-33

**No linting tools configured.** The `STEERING.md` recommends running `tfsec` or `checkov` before deployment, but no configuration files for these tools exist in the repository.

## Import Organization

**Not applicable** — Terraform uses declarative resource blocks, not imports. Dependencies are resolved automatically by the Terraform graph.

## Module Usage

**External Module:**
- CloudPosse `terraform-null-label` v0.25.0 — used via `context.tf` for consistent naming/tagging
- Referenced as `module.this` throughout all `.tf` files

**Module source pattern:**
```hcl
module "this" {
  source  = "cloudposse/label/null"
  version = "0.25.0"
  # ... context variables
}
```
See: `context.tf` lines 23-46

## File Organization by Concern

Follow the domain-separation pattern:
- `main.tf` — Terraform/provider configuration, backend
- `variables.tf` — All variable declarations (including context.tf variables)
- `outputs.tf` — All output declarations
- `context.tf` — CloudPosse null-label module (copy from upstream, do not edit)
- `vpc.tf` — VPC, subnets, internet gateway, route tables
- `iam-ecs.tf` — IAM roles for ECS
- `terraform.tfvars` — Variable values

**When adding new resources,** create a new `.tf` file named for the domain:
- ECS cluster/service/task → `ecs.tf`
- ALB/target groups/listeners → `alb.tf`
- RDS database → `rds.tf`
- Security groups → `security-groups.tf` or inline in the domain file
- Route53/ACM → `dns.tf` or `route53.tf`

## Comments

**Section Headers:**
- Use `# <Resource Type>` comments above resource blocks to label sections
- Examples from `vpc.tf`: `# VPC`, `# Internet Gateway`, `# Public Subnets`, `# Private Subnets`

**Inline Comments:**
- Use `# <explanation>` for policy attachments or non-obvious configurations
- Example from `iam-ecs.tf` line 26: `# Attach AWS managed policy for ECS task execution`
- Example from `iam-ecs.tf` line 32: `# ECS Task Role (for application permissions)`

**No JSDoc/TSDoc equivalent** — this is HCL. Use variable `description` fields and resource comments.

## Error Handling

**Terraform-specific patterns:**
- Use `validation` blocks in variable definitions for input validation
- See `context.tf` lines 79-87 for validation examples
- Use `lifecycle` blocks for resource management (referenced in `STEERING.md`)

## Iteration Patterns

**Use `count` with `length()` for indexed iteration:**
```hcl
resource "aws_subnet" "public" {
  count             = length(var.availability_zones)
  availability_zone = var.availability_zones[count.index]
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
}
```
See: `vpc.tf` lines 28-43

**Use splat expressions for outputs:**
```hcl
output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}
```
See: `outputs.tf` lines 6-9

## CIDR Addressing Pattern

**Use `cidrsubnet()` function** instead of hardcoded CIDR blocks:
- Public subnets: `cidrsubnet(var.vpc_cidr, 8, count.index)` — offsets 0, 1, 2
- Private subnets: `cidrsubnet(var.vpc_cidr, 8, count.index + 10)` — offsets 10, 11, 12
See: `vpc.tf` lines 31, 49

## IAM Policy Patterns

**Inline assume role policies** use `jsonencode()`:
```hcl
assume_role_policy = jsonencode({
  Version = "2012-10-17"
  Statement = [
    {
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }
  ]
})
```
See: `iam-ecs.tf` lines 5-16

**Managed policy attachments** use separate `aws_iam_role_policy_attachment` resources:
See: `iam-ecs.tf` lines 27-30

## Security Conventions (from STEERING.md)

- **No hardcoded secrets** — use variables marked `sensitive = true`, or AWS Secrets Manager / Parameter Store
- **Least privilege** — grant only necessary permissions
- **Encryption by default** — enable for all storage and databases
- **Private subnets** for applications and databases; public subnets only for load balancers

## State Management

- **Backend:** S3 with DynamoDB locking (configured in `main.tf` lines 15-21)
- **State bucket:** `dna-stag-terraform-state`
- **Lock table:** `dna-stag-terraform-locks`
- **Encryption:** enabled (`encrypt = true`)

## Principles (from STEERING.md)

1. **DRY** — Use modules, variables, and `count`/`for_each`; change values in ONE place
2. **KISS** — Readability over cleverness; avoid complex conditionals; use `locals` maps instead of nested ternaries
3. **Security First** — Encryption, least privilege, no hardcoded secrets
4. **Immutability** — No manual changes; use `lifecycle { create_before_destroy = true }` for critical resources
5. **Idempotency** — No side effects from repeated runs; use state locking
6. **Modularity** — Separate concerns by layer (network, database, application, DNS)
7. **Consistent Naming** — All resources use `module.this.id` and `module.this.tags`

---

*Convention analysis: 2026-03-17*
