# Infrastructure as Code - Core Principles

This document outlines the fundamental principles to follow when creating infrastructure via IaC.

## 1. DRY (Don't Repeat Yourself)

Duplication is the enemy of consistency.

**Rules:**
- Use modules for reusable components (e.g., "Standard Web Server")
- Use variables and locals to customize without rewriting logic
- If you need to change a value, change it in ONE place only

**Example:**
```hcl
# BAD: Repeated CIDR blocks
resource "aws_subnet" "public_1" {
  cidr_block = "10.0.1.0/24"
}
resource "aws_subnet" "public_2" {
  cidr_block = "10.0.2.0/24"
}

# GOOD: Use count or for_each with variables
resource "aws_subnet" "public" {
  count      = length(var.availability_zones)
  cidr_block = cidrsubnet(var.vpc_cidr, 8, count.index)
}
```

## 2. KISS (Keep It Simple, Stupid)

Avoid over-engineering.

**Rules:**
- Readability over cleverness - junior engineers should understand your code in 10 minutes
- Favor flat directory structures over deep nesting
- Avoid complex conditional logic
- If it's hard to explain, it's too complex

**Example:**
```hcl
# BAD: Complex nested conditionals
resource "aws_instance" "app" {
  instance_type = var.env == "prod" ? (var.size == "large" ? "t3.large" : "t3.medium") : "t3.micro"
}

# GOOD: Clear variable mapping
locals {
  instance_types = {
    prod-large  = "t3.large"
    prod-medium = "t3.medium"
    dev         = "t3.micro"
  }
}
resource "aws_instance" "app" {
  instance_type = local.instance_types["${var.env}-${var.size}"]
}
```

## 3. Security First (Shift Left)

Security is hardcoded into templates, not an afterthought.

**Rules:**
- **Least Privilege:** Grant only necessary permissions
- **No Hardcoded Secrets:** Use AWS Secrets Manager, Parameter Store, or HashiCorp Vault
- **Static Analysis:** Run tfsec or checkov before deployment
- **Encryption:** Enable encryption by default for storage and databases

**Example:**
```hcl
# BAD: Hardcoded credentials
resource "aws_db_instance" "main" {
  username = "admin"
  password = "MyPassword123!"
}

# GOOD: Use variables marked as sensitive
resource "aws_db_instance" "main" {
  username = var.db_username
  password = var.db_password  # sensitive = true in variables.tf
}
```

## 4. Immutability

Destroy and redeploy instead of patching.

**Rules:**
- **No Manual Changes:** If it wasn't done in code, it didn't happen
- Manual UI tweaks cause state drift and break IaC
- Replace resources instead of modifying them in place
- Configuration drift is a bug, not a feature

**Example:**
```hcl
# GOOD: Force replacement on critical changes
resource "aws_instance" "app" {
  ami           = var.ami_id
  instance_type = var.instance_type
  
  lifecycle {
    create_before_destroy = true
  }
}
```

## 5. Idempotency

Running the same code multiple times produces the same result.

**Rules:**
- No side effects from repeated runs
- Use robust state management (S3 backend with DynamoDB locking)
- Track current state vs desired state
- Plan before apply to verify changes

**Example:**
```hcl
# GOOD: Idempotent backend configuration
terraform {
  backend "s3" {
    bucket         = "terraform-state"
    key            = "project/terraform.tfstate"
    region         = "eu-west-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}
```

## 6. Modularity and Decoupling

Separate concerns to minimize blast radius.

**Rules:**
- Don't build monolithic templates
- Separate network, database, and application layers
- If you make a mistake in one layer, don't risk others
- Use separate state files for different layers

**Example:**
```
# GOOD: Separated structure
├── network/          # VPC, subnets, NAT
├── database/         # RDS, security groups
├── application/      # ECS, ALB
└── dns/             # Route53, ACM
```

## 7. Consistent Naming with Context

Use context.tf (terraform-null-label) for all resource names.

**Rules:**
- **Every AWS resource name** must use `module.this.id` or `module.this.tags`
- Ensures consistent naming across all resources
- Makes resources easily identifiable and searchable
- Enables automatic tagging with namespace, environment, name

**Example:**
```hcl
# BAD: Hardcoded names
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "my-vpc"
  }
}

# GOOD: Using context.tf
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr
  
  tags = merge(
    module.this.tags,
    {
      Name = "${module.this.id}-vpc"
    }
  )
}

# GOOD: Resource naming
resource "aws_ecs_cluster" "main" {
  name = "${module.this.id}-cluster"
  tags = module.this.tags
}
```

**Context Variables:**
```hcl
# terraform.tfvars
namespace   = "dna"
environment = "interview"
name        = "ecs"

# Results in names like: dna-interview-ecs-vpc, dna-interview-ecs-cluster
```

## Quick Checklist

Before committing IaC code, verify:

- [ ] No duplicated code (DRY)
- [ ] Code is readable and simple (KISS)
- [ ] No hardcoded secrets
- [ ] Encryption enabled where applicable
- [ ] No manual changes documented
- [ ] State backend configured
- [ ] Resources properly separated by concern
- [ ] Variables used for customization
- [ ] Outputs defined for important values
- [ ] Tags applied consistently
- [ ] All resource names use `module.this.id` or `module.this.tags`
- [ ] Context variables defined (namespace, environment, name)

## Common Anti-Patterns to Avoid

1. **Hardcoded values** - Use variables
2. **Copy-paste code** - Use modules
3. **Manual UI changes** - Update code instead
4. **Monolithic templates** - Separate by layer
5. **No state locking** - Use DynamoDB or equivalent
6. **Secrets in code** - Use secret management
7. **No static analysis** - Run security scans
8. **Complex logic** - Keep it simple
9. **Hardcoded resource names** - Use context.tf for naming
10. **Inconsistent tagging** - Use module.this.tags

## Remember

> "Infrastructure as Code is software engineering for hardware. Treat it like production code: review it, test it, version it, and never touch production manually."
