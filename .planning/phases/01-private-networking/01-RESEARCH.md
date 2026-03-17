# Phase 1: Private Networking - Research

**Researched:** 2026-03-17
**Domain:** AWS VPC networking — NAT Gateway, Elastic IP, route tables (Terraform HCL)
**Confidence:** HIGH

## Summary

Phase 1 adds outbound internet connectivity for private subnets by creating a NAT Gateway with an Elastic IP, a private route table with a default route through the NAT Gateway, and route table associations for all 3 private subnets. This is the foundational networking prerequisite — without it, ECS Fargate tasks in private subnets cannot pull container images or send logs.

The existing VPC scaffold in `vpc.tf` provides the VPC, internet gateway, 3 public subnets, 3 private subnets, and a public route table with associations. The gap is: **private subnets have no route table and no internet egress path**. This phase closes that gap with exactly 4 new resources (EIP, NAT Gateway, route table, 3 route table associations).

All resources use well-established Terraform AWS provider patterns. The implementation is low-complexity and follows the existing codebase conventions (CloudPosse null-label naming, count-based iteration, domain-file organization). The STACK.md research has already verified every resource argument against provider ~> 5.0 docs.

**Primary recommendation:** Add all 4 NAT Gateway resources to the existing `vpc.tf` file, following the established patterns for naming, tagging, and iteration.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| NET-01 | Private subnets can route outbound traffic to the internet via NAT Gateway | NAT Gateway in public subnet + private route table with 0.0.0.0/0 → NAT GW route enables outbound traffic from private subnets |
| NET-02 | NAT Gateway has a dedicated Elastic IP in a public subnet | `aws_eip.nat` with `domain = "vpc"` + `aws_nat_gateway.main` placed in `aws_subnet.public[0].id` |
| NET-03 | All 3 private subnets are associated with a route table that routes through the NAT Gateway | `aws_route_table_association.private` with `count = length(aws_subnet.private)` associates all 3 private subnets to the private route table |
</phase_requirements>

## Standard Stack

### Core

| Resource Type | Logical Name | Purpose | Why Standard |
|---------------|--------------|---------|--------------|
| `aws_eip` | `nat` | Elastic IP for NAT Gateway | NAT Gateway requires a static public IP for outbound traffic translation |
| `aws_nat_gateway` | `main` | NAT Gateway for private subnet egress | Standard AWS pattern for private subnet internet access |
| `aws_route_table` | `private` | Route table for private subnets | Routes 0.0.0.0/0 through NAT Gateway |
| `aws_route_table_association` | `private[0..2]` | Associates private subnets to route table | Connects all 3 private subnets to the NAT route |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Single NAT Gateway | Per-AZ NAT Gateways (3x) | HA but ~$100/month vs ~$32/month. Explicitly out of scope per REQUIREMENTS.md |
| NAT Gateway | VPC Endpoints for ECR/S3/CloudWatch | Would eliminate NAT for AWS service calls but adds complexity. Explicitly out of scope |
| NAT Gateway | NAT Instance (EC2) | Cheaper but requires instance management. Not appropriate for interview |

**No installation needed** — all resources are native Terraform AWS provider resources already available via `hashicorp/aws ~> 5.0`.

## Architecture Patterns

### Resource Placement in Existing File

```
vpc.tf (EXTEND — add after existing line 84)
├── aws_eip.nat                          # Elastic IP for NAT
├── aws_nat_gateway.main                 # NAT Gateway in public[0]
├── aws_route_table.private              # Private route table with 0.0.0.0/0 → NAT
└── aws_route_table_association.private   # count=3, associates all private subnets
```

**Rationale for extending `vpc.tf`:** These are networking resources that logically belong with the existing VPC scaffold. The STACK.md research recommends `vpc.tf`, and the FEATURES.md research suggests a separate `nat.tf` — but extending `vpc.tf` is more consistent with the existing pattern where all networking (VPC, subnets, IGW, route tables, associations) lives in one file. The existing public route table and associations are already in `vpc.tf`.

### Pattern: Single NAT Gateway Shared by All Private Subnets

**What:** One NAT Gateway in `public[0]` subnet, one route table, all 3 private subnets associated.
**When to use:** Non-production, cost-sensitive environments where HA is not critical.
**Example:**

```hcl
# Source: STACK.md (verified against Terraform registry docs)

# Elastic IP for NAT Gateway
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = merge(
    module.this.tags,
    { Name = "${module.this.id}-nat-eip" }
  )
}

# NAT Gateway
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = merge(
    module.this.tags,
    { Name = "${module.this.id}-nat" }
  )

  depends_on = [aws_internet_gateway.main]
}

# Private Route Table
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = merge(
    module.this.tags,
    { Name = "${module.this.id}-private-rt" }
  )
}

# Private Route Table Associations
resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
```

### Pattern Alignment with Existing Codebase

| Convention | How This Phase Follows It |
|------------|---------------------------|
| `module.this.id` prefix | All Name tags use `"${module.this.id}-<suffix>"` |
| `module.this.tags` merge | All resources use `tags = merge(module.this.tags, { Name = "..." })` |
| `count` with `length()` | Route table associations use `count = length(aws_subnet.private)` — matches existing `aws_route_table_association.public` pattern |
| Resource naming (`main`) | NAT Gateway uses `main` (singleton), matching `aws_vpc.main`, `aws_internet_gateway.main` |
| Section comments | Add `# NAT Gateway`, `# Private Route Table`, etc. matching existing `# VPC`, `# Internet Gateway` style |

### Anti-Patterns to Avoid

- **Separate `nat.tf` file:** While reasonable, the existing codebase keeps all networking in `vpc.tf`. Adding a separate file for 4 resources that are tightly coupled to VPC networking breaks the established pattern.
- **Using `aws_route` as separate resource:** The existing public route table uses an inline `route {}` block. Follow the same pattern for the private route table for consistency.
- **Hardcoding subnet index:** Use `aws_subnet.public[0].id` (the first public subnet) — this is explicit and acceptable for a single NAT Gateway. Don't over-engineer with `for_each`.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| NAT for private subnets | EC2 NAT instance | `aws_nat_gateway` | Managed service, no instance maintenance, built-in HA within AZ |
| Elastic IP management | Manual IP allocation | `aws_eip` with `domain = "vpc"` | Terraform manages lifecycle automatically |
| Route table associations | Manual subnet-RT mapping | `count`-based `aws_route_table_association` | Matches existing pattern, scales with subnet count |

## Common Pitfalls

### Pitfall 1: Missing `depends_on` for NAT Gateway → Internet Gateway

**What goes wrong:** `terraform apply` creates NAT Gateway before Internet Gateway is fully attached to VPC. AWS API returns an error.
**Why it happens:** Terraform can't infer this dependency from resource references — NAT Gateway references a subnet, not the IGW directly.
**How to avoid:** Add `depends_on = [aws_internet_gateway.main]` on `aws_nat_gateway.main`.
**Warning signs:** NAT Gateway creation fails during `terraform apply`.
**Confidence:** HIGH — verified in Terraform registry docs and multiple implementation guides.

### Pitfall 2: Using `vpc = true` on `aws_eip` with Provider ~> 5.0

**What goes wrong:** `terraform plan` fails with deprecation/removal error.
**Why it happens:** `vpc = true` was the old syntax. Deprecated in provider 5.0, replaced by `domain = "vpc"`.
**How to avoid:** Always use `domain = "vpc"`.
**Warning signs:** Immediate plan error.
**Confidence:** HIGH — verified in Terraform AWS provider v5 upgrade guide (registry.terraform.io).

### Pitfall 3: NAT Gateway Placed in Private Subnet

**What goes wrong:** NAT Gateway has no internet connectivity itself — it needs to be in a public subnet (with an IGW route) to function.
**Why it happens:** Confusion between "which subnet needs internet" (private) and "where to put the NAT" (public).
**How to avoid:** Always place NAT Gateway in a **public** subnet: `subnet_id = aws_subnet.public[0].id`.
**Warning signs:** NAT Gateway creates successfully but private subnets still can't reach the internet.
**Confidence:** HIGH — fundamental AWS networking concept.

### Pitfall 4: Tag Duplication with Provider `default_tags`

**What goes wrong:** Tags defined on resources that overlap with provider `default_tags` can cause perpetual diffs.
**Why it happens:** `main.tf` sets `default_tags { tags = module.this.tags }`. Resources also merge `module.this.tags`.
**How to avoid:** This is an existing pattern in the codebase (all resources in `vpc.tf` do this). Follow the same pattern for consistency — the merge is intentional and works. Provider default_tags and resource tags merge gracefully in provider 5.x.
**Warning signs:** `terraform plan` shows tag changes on every run.
**Confidence:** HIGH — existing codebase already handles this.

## Code Examples

Verified patterns from STACK.md research (cross-referenced with Terraform registry docs):

### Complete Implementation (all 4 resources)

```hcl
# Source: STACK.md + Terraform registry (aws_eip, aws_nat_gateway, aws_route_table)

# NAT Gateway
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = merge(
    module.this.tags,
    {
      Name = "${module.this.id}-nat-eip"
    }
  )
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = merge(
    module.this.tags,
    {
      Name = "${module.this.id}-nat"
    }
  )

  depends_on = [aws_internet_gateway.main]
}

# Private Route Table
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = merge(
    module.this.tags,
    {
      Name = "${module.this.id}-private-rt"
    }
  )
}

# Private Route Table Association
resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
```

### Verification Commands

```bash
# Verify NAT Gateway resource with EIP in public subnet
tofu plan | grep -A5 "aws_nat_gateway"

# Verify route table has 0.0.0.0/0 → NAT route
tofu plan | grep -A10 "aws_route_table.private"

# Verify all 3 private subnets are associated
tofu plan | grep "aws_route_table_association.private"

# Full plan check (should show exactly 5 new resources: EIP + NAT GW + RT + 3 associations)
tofu plan
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `vpc = true` on `aws_eip` | `domain = "vpc"` | AWS provider 5.0 (May 2023) | `vpc = true` deprecated/removed. Must use `domain`. |
| Inline route in `aws_route_table` vs separate `aws_route` | Both supported, inline preferred for simple cases | Ongoing | Codebase uses inline `route {}` blocks — follow this pattern |

**No deprecated patterns in scope.** All resources use current provider 5.x syntax.

## Open Questions

1. **Tag duplication behavior**
   - What we know: The codebase uses `tags = merge(module.this.tags, { Name = "..." })` AND provider `default_tags` includes `module.this.tags`. This means tags like `namespace`, `environment` appear in both places.
   - What's unclear: Whether this causes warnings in the specific Terraform/OpenTofu version used.
   - Recommendation: Follow the existing pattern — it works in the codebase today. If warnings appear, they're cosmetic.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Terraform/OpenTofu plan validation (no separate test framework) |
| Config file | N/A — uses `tofu plan` output |
| Quick run command | `tofu plan` |
| Full suite command | `tofu plan -detailed-exitcode` (exit 0=no changes, 1=error, 2=changes present) |

### Phase Requirements -> Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| NET-01 | Private subnets route outbound via NAT | smoke (plan) | `tofu plan \| grep "aws_nat_gateway.main"` | N/A (plan output) |
| NET-02 | NAT GW has EIP in public subnet | smoke (plan) | `tofu plan \| grep "aws_eip.nat"` | N/A (plan output) |
| NET-03 | All 3 private subnets associated with NAT route table | smoke (plan) | `tofu plan \| grep "aws_route_table_association.private"` | N/A (plan output) |

### Sampling Rate

- **Per task commit:** `tofu plan` — verify no errors and expected resources appear
- **Per wave merge:** `tofu plan -detailed-exitcode` — verify clean plan
- **Phase gate:** `tofu plan` shows exactly: 1 EIP, 1 NAT Gateway, 1 route table (with 0.0.0.0/0 → NAT route), 3 route table associations

### Wave 0 Gaps

None — `tofu plan` is the validation mechanism and requires no additional test infrastructure. The existing Terraform configuration is sufficient to validate all 3 requirements through plan output inspection.

## Sources

### Primary (HIGH confidence)
- Terraform AWS provider registry: `aws_eip` resource — `domain = "vpc"` argument, `vpc` deprecated (registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eip)
- Terraform AWS provider registry: `aws_nat_gateway` resource — `allocation_id`, `subnet_id`, `depends_on` pattern (registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/nat_gateway)
- Terraform AWS provider registry: `aws_route_table`, `aws_route_table_association` — inline route blocks, count-based associations
- Terraform AWS provider v5 upgrade guide — `vpc = true` → `domain = "vpc"` migration (registry.terraform.io/providers/hashicorp/aws/latest/docs/guides/version-5-upgrade)
- Project STACK.md — complete resource definitions verified against provider docs
- Project FEATURES.md — feature dependencies and ordering verified
- Project PITFALLS.md — pitfalls 2, 3, 8 directly relevant to this phase

### Secondary (MEDIUM confidence)
- Multiple blog sources (oneuptime.com, awstip.com) — confirm NAT Gateway patterns, cross-verified with official docs
- terraform-aws-modules/terraform-aws-vpc — reference implementation confirming single NAT Gateway pattern

### Tertiary (LOW confidence)
- None — all findings verified with primary sources

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — 4 resources, all well-documented in Terraform registry, verified in STACK.md
- Architecture: HIGH — follows existing codebase patterns exactly, extends vpc.tf
- Pitfalls: HIGH — all pitfalls verified against official docs and confirmed in project PITFALLS.md research

**Research date:** 2026-03-17
**Valid until:** 2026-04-17 (stable Terraform resources, unlikely to change)
