# Codebase Structure

**Analysis Date:** 2026-03-17

## Directory Layout

```
dna-task-infra-v2/
├── .gitignore              # Ignores .terraform/, *.tfstate, *.tfvars, credentials
├── .planning/              # Planning and analysis documents (not Terraform)
│   └── codebase/           # Codebase mapping documents
├── context.tf              # CloudPosse null-label module + context variables
├── iam-ecs.tf              # IAM roles for ECS task execution and task
├── main.tf                 # Terraform config: providers, backend, required_providers
├── outputs.tf              # Terraform outputs (vpc_id, subnet IDs)
├── README.md               # Interview task instructions (3 exercises)
├── setup/                  # Interviewer setup resources (not part of Terraform)
│   └── interview-candidate-policy.json  # IAM policy for candidate AWS access
├── STEERING.md             # IaC principles and conventions guide
├── terraform.tfvars        # Variable values (namespace, environment, CIDR, etc.)
├── variables.tf            # Custom variable declarations (region, vpc_cidr, AZs)
└── vpc.tf                  # VPC, subnets, IGW, route tables
```

## Directory Purposes

**Root (`/`):**
- Purpose: Single Terraform root module — all `.tf` files are processed together
- Contains: All Terraform configuration files (`.tf`), variable files (`.tfvars`), documentation (`.md`)
- Key files: `main.tf` (entry point), `context.tf` (naming), `vpc.tf` (networking), `iam-ecs.tf` (IAM)

**`setup/`:**
- Purpose: Interviewer-only setup resources, not part of Terraform execution
- Contains: IAM policy JSON for creating candidate AWS credentials
- Key files: `setup/interview-candidate-policy.json`

**`.planning/`:**
- Purpose: Planning and analysis documentation
- Contains: Codebase mapping documents
- Generated: Yes (by tooling)
- Committed: May be committed for reference

## Key File Locations

**Entry Points:**
- `main.tf`: Terraform/OpenTofu entry — provider config, backend config, version constraints

**Configuration:**
- `terraform.tfvars`: Runtime variable values (namespace=`dna`, environment=`interview`, name=`ecs`, vpc_cidr=`10.64.0.0/20`)
- `variables.tf`: Custom variable declarations with types and defaults
- `context.tf`: CloudPosse context variables (~20 variables for naming/tagging)

**Core Infrastructure:**
- `vpc.tf`: VPC (`aws_vpc.main`), public subnets (`aws_subnet.public`), private subnets (`aws_subnet.private`), internet gateway (`aws_internet_gateway.main`), route tables
- `iam-ecs.tf`: ECS task execution role (`aws_iam_role.ecs_task_execution`), ECS task role (`aws_iam_role.ecs_task`)

**Naming/Tagging:**
- `context.tf`: `module.this` (cloudposse/label/null v0.25.0) — provides `module.this.id` and `module.this.tags`

**Outputs:**
- `outputs.tf`: Exposes `vpc_id`, `public_subnet_ids`, `private_subnet_ids`

**Documentation:**
- `README.md`: Full interview exercise instructions (3 exercises with requirements and success criteria)
- `STEERING.md`: IaC principles guide (DRY, KISS, Security First, Immutability, Idempotency, Modularity, Naming)

**Setup/Admin:**
- `setup/interview-candidate-policy.json`: AWS IAM policy granting candidate access to required services

## Naming Conventions

**Files:**
- Terraform files: lowercase with hyphens, `.tf` extension (e.g., `iam-ecs.tf`, `vpc.tf`)
- Domain-based splitting: each file covers one infrastructure domain (networking, IAM, outputs, etc.)
- `main.tf` reserved for provider/backend config only (no resources)
- `context.tf` is a standard CloudPosse convention — do not rename

**Resources:**
- Resource names: `snake_case` Terraform identifiers (e.g., `aws_iam_role.ecs_task_execution`)
- AWS names: `"${module.this.id}-<descriptive-suffix>"` pattern (e.g., `dna-interview-ecs-vpc`)
- Use `main` as the resource local name for primary/singleton resources (e.g., `aws_vpc.main`)

**Variables:**
- `snake_case` names (e.g., `vpc_cidr`, `availability_zones`, `aws_region`)
- Include `description` and `type` for every variable
- Use `default` only when a sensible default exists

**Tags:**
- Always merge `module.this.tags` with a resource-specific `Name` tag:
  ```hcl
  tags = merge(
    module.this.tags,
    { Name = "${module.this.id}-<suffix>" }
  )
  ```

## Where to Add New Code

**New Infrastructure Resource (e.g., ECS cluster, ALB, RDS):**
- Create a new `.tf` file in the project root named by domain: e.g., `ecs.tf`, `alb.tf`, `rds.tf`, `route53.tf`, `acm.tf`
- Follow the pattern: one file per AWS service domain
- Reference `module.this.id` for naming and `module.this.tags` for tagging
- Reference existing resources: `aws_vpc.main.id`, `aws_subnet.public[*].id`, `aws_subnet.private[*].id`

**New Variables:**
- Add to `variables.tf` for custom variables (not context-related)
- Follow format: `type`, `description`, optional `default`

**New Outputs:**
- Add to `outputs.tf` with a descriptive `description` field

**New Security Groups:**
- Create in a domain-specific file (e.g., security groups for ALB go in `alb.tf`, for ECS in `ecs.tf`, for RDS in `rds.tf`)
- Alternatively, create a dedicated `security-groups.tf` if grouping all SGs together

**New IAM Roles/Policies:**
- Add to `iam-ecs.tf` if ECS-related, or create a new `iam-<service>.tf` file for other services

## File Organization Guidance

**Recommended file structure for completed exercises:**
```
dna-task-infra-v2/
├── main.tf                 # Provider, backend (DO NOT add resources here)
├── context.tf              # Naming module (DO NOT modify)
├── variables.tf            # All custom variables
├── outputs.tf              # All outputs
├── terraform.tfvars        # Variable values
├── vpc.tf                  # VPC, subnets, IGW, route tables (pre-built)
├── iam-ecs.tf              # ECS IAM roles (pre-built)
├── ecs.tf                  # [Exercise 1] ECS cluster, task definition, service
├── alb.tf                  # [Exercise 1] ALB, listener, target group, ALB SG
├── security-groups.tf      # [Exercise 1] ECS security group (or inline in ecs.tf)
├── rds.tf                  # [Exercise 2] RDS instance, subnet group, RDS SG
├── route53.tf              # [Exercise 3] Hosted zone, DNS records
├── acm.tf                  # [Exercise 3] ACM certificate, DNS validation
└── ...
```

## Special Directories

**`.terraform/`:**
- Purpose: Terraform provider plugins and module cache
- Generated: Yes (by `tofu init`)
- Committed: No (in `.gitignore`)

**`setup/`:**
- Purpose: Interviewer admin resources for AWS account setup
- Generated: No (manually created)
- Committed: Yes
- Note: Not processed by Terraform — contains reference JSON only

## Existing Resource References

When adding new resources, reference these existing resources:

| Resource | Terraform Reference | Description |
|----------|-------------------|-------------|
| VPC | `aws_vpc.main.id` | Main VPC |
| Public Subnets | `aws_subnet.public[*].id` | 3 public subnets (one per AZ) |
| Private Subnets | `aws_subnet.private[*].id` | 3 private subnets (one per AZ) |
| ECS Task Execution Role | `aws_iam_role.ecs_task_execution.arn` | For ECS task definitions |
| ECS Task Role | `aws_iam_role.ecs_task.arn` | For ECS task application permissions |
| Naming ID | `module.this.id` | Prefix: `dna-interview-ecs` |
| Tags | `module.this.tags` | Standard tags for all resources |

---

*Structure analysis: 2026-03-17*
