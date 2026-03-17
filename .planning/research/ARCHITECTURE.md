# Architecture Patterns: ECS + ALB Integration with Existing Terraform Scaffold

**Domain:** AWS ECS Fargate + ALB Terraform infrastructure
**Researched:** 2026-03-17
**Overall confidence:** HIGH — patterns verified against existing codebase, official Terraform registry docs, and multiple production references

## Recommended Architecture

### Overview

The existing scaffold uses a **flat root module with domain-based .tf file splitting**. New ECS/ALB resources follow this same pattern: one `.tf` file per AWS service domain, all resources referencing `module.this.id` for naming and `module.this.tags` for tagging. No child modules — raw resources only.

```
┌─────────────────────────────────────────────────────────────┐
│                        INTERNET                              │
│                           │                                  │
│                    ┌──────┴──────┐                           │
│                    │  IGW (exists)│                           │
│                    └──────┬──────┘                           │
│                           │                                  │
│  ┌────────────────────────┼────────────────────────┐        │
│  │ PUBLIC SUBNETS (x3)    │                        │        │
│  │                  ┌─────┴──────┐                  │        │
│  │                  │    ALB     │  ← SG: 80/tcp   │        │
│  │                  │ (alb.tf)  │    from 0.0.0.0/0│        │
│  │                  └─────┬──────┘                  │        │
│  │                        │                         │        │
│  │  ┌─────────────────────┼──────────────────────┐  │        │
│  │  │ NAT GW (vpc.tf)     │                      │  │        │
│  │  │ EIP ──► NAT ──► Private RT                 │  │        │
│  │  └─────────────────────┼──────────────────────┘  │        │
│  └────────────────────────┼────────────────────────┘        │
│                           │                                  │
│  ┌────────────────────────┼────────────────────────┐        │
│  │ PRIVATE SUBNETS (x3)   │                        │        │
│  │                  ┌─────┴──────┐                  │        │
│  │                  │ ECS Tasks  │  ← SG: 5678/tcp │        │
│  │                  │ (ecs.tf)   │    from ALB SG   │        │
│  │                  └────────────┘                  │        │
│  │                                                  │        │
│  │  CloudWatch Logs ← /aws/ecs/dna-interview-ecs   │        │
│  └──────────────────────────────────────────────────┘        │
└─────────────────────────────────────────────────────────────┘
```

### Component Boundaries

| Component | File | Responsibility | Communicates With |
|-----------|------|---------------|-------------------|
| NAT Gateway + EIP + Private RT | `vpc.tf` (modify existing) | Enables private subnet egress to internet | IGW (outbound), private subnets (route table) |
| ALB + Listener + Target Group + ALB SG | `alb.tf` (new) | HTTP ingress, health checks, traffic distribution | Internet (inbound), ECS tasks (forwarding) |
| ECS Cluster + Task Def + Service + ECS SG + CW Logs | `ecs.tf` (new) | Container orchestration and application runtime | ALB (receives traffic), NAT GW (image pull, logs), IAM roles (permissions) |
| Outputs | `outputs.tf` (modify existing) | Expose ALB DNS name, ECS cluster name | Consumers of `tofu output` |

## File Organization: New and Modified Files

### Files to CREATE (2 new files)

**`alb.tf`** — Application Load Balancer domain
- `aws_security_group.alb` — HTTP from internet
- `aws_lb.main` — ALB in public subnets
- `aws_lb_target_group.main` — IP type target group with health checks
- `aws_lb_listener.http` — Port 80 HTTP listener forwarding to target group

**`ecs.tf`** — ECS domain
- `aws_security_group.ecs` — Container port from ALB SG only
- `aws_cloudwatch_log_group.ecs` — Container log group
- `aws_ecs_cluster.main` — Fargate cluster with Container Insights
- `aws_ecs_task_definition.main` — http-echo container definition
- `aws_ecs_service.main` — Fargate service in private subnets

### Files to MODIFY (2 existing files)

**`vpc.tf`** — Add NAT Gateway infrastructure
- `aws_eip.nat` — Elastic IP for NAT Gateway
- `aws_nat_gateway.main` — Single NAT GW in first public subnet
- `aws_route_table.private` — Private route table with 0.0.0.0/0 → NAT GW
- `aws_route_table_association.private` — Associate private subnets with private RT

**`outputs.tf`** — Add new outputs
- `alb_dns_name` — ALB DNS for curl testing
- `ecs_cluster_name` — ECS cluster name

### Files NOT to modify

| File | Reason |
|------|--------|
| `main.tf` | Provider/backend config only, no resources |
| `context.tf` | CloudPosse standard, do not modify |
| `iam-ecs.tf` | IAM roles already created and sufficient |
| `variables.tf` | No new variables needed — all values can be hardcoded or derived from existing vars |
| `terraform.tfvars` | No new variable values needed |

## Integration Points: Specific Resource References

### From Existing Resources (consumed by new resources)

| Existing Resource | Terraform Reference | Consumed By | How Used |
|-------------------|---------------------|-------------|----------|
| VPC | `aws_vpc.main.id` | ALB SG, ECS SG, Target Group | VPC ID for security groups and target group |
| Public Subnets | `aws_subnet.public[*].id` | ALB, NAT Gateway | ALB placement, NAT GW placement |
| Private Subnets | `aws_subnet.private[*].id` | ECS Service, Private RT Assoc | ECS task ENI placement, route table association |
| IGW | `aws_internet_gateway.main.id` | (indirect via existing public RT) | Already routes public subnet traffic |
| ECS Task Execution Role | `aws_iam_role.ecs_task_execution.arn` | ECS Task Definition | `execution_role_arn` — for ECR pull + CW logs |
| ECS Task Role | `aws_iam_role.ecs_task.arn` | ECS Task Definition | `task_role_arn` — for application permissions |
| Naming ID | `module.this.id` | All new resources | Name prefix: `dna-interview-ecs-<suffix>` |
| Tags | `module.this.tags` | All new resources | Consistent tagging |

### Cross-File References (new resources referencing each other)

| Source (in file) | Reference | Target (in file) | Purpose |
|------------------|-----------|-------------------|---------|
| ECS Service (`ecs.tf`) | `aws_lb_target_group.main.arn` | Target Group (`alb.tf`) | Register ECS tasks with ALB |
| ECS Service (`ecs.tf`) | `aws_security_group.ecs.id` | ECS SG (`ecs.tf`) | Task ENI security group |
| ALB (`alb.tf`) | `aws_security_group.alb.id` | ALB SG (`alb.tf`) | Load balancer security group |
| ECS SG ingress (`ecs.tf`) | `aws_security_group.alb.id` | ALB SG (`alb.tf`) | Allow traffic FROM ALB only |
| ALB Listener (`alb.tf`) | `aws_lb_target_group.main.arn` | Target Group (`alb.tf`) | Forward action target |
| ECS Task Def (`ecs.tf`) | `aws_cloudwatch_log_group.ecs.name` | CW Log Group (`ecs.tf`) | Container log configuration |
| Private RT (`vpc.tf`) | `aws_nat_gateway.main.id` | NAT GW (`vpc.tf`) | Default route for private subnets |
| NAT GW (`vpc.tf`) | `aws_eip.nat.id` | EIP (`vpc.tf`) | Elastic IP allocation |

## Data Flow

### HTTP Request Flow (runtime)

```
Client → IGW → ALB (public subnet, port 80)
  → Listener evaluates → forwards to Target Group
  → Target Group routes to healthy ECS task IP (private subnet, port 5678)
  → Task responds → ALB → Client
```

### ECS Task Startup Flow (why NAT Gateway matters)

```
ECS Service starts task → ENI created in private subnet
  → Task needs to pull image from Docker Hub (hashicorp/http-echo)
  → Outbound traffic: private subnet → private RT → NAT GW → IGW → internet
  → Image pulled, container starts
  → Task sends logs to CloudWatch (same outbound path via NAT)
  → Task registers with Target Group (AWS internal API)
  → ALB health check passes → target marked healthy
```

### Terraform Dependency Graph

```
Level 0 (existing, already applied):
  aws_vpc.main
  aws_subnet.public[*]
  aws_subnet.private[*]
  aws_internet_gateway.main
  aws_iam_role.ecs_task_execution
  aws_iam_role.ecs_task
  module.this

Level 1 (NAT Gateway — enables private subnet egress):
  aws_eip.nat
  aws_nat_gateway.main ← depends on: aws_eip.nat, aws_subnet.public[0]
  aws_route_table.private ← depends on: aws_vpc.main, aws_nat_gateway.main
  aws_route_table_association.private[*] ← depends on: aws_route_table.private, aws_subnet.private[*]

Level 1 (ALB infra — can parallelize with NAT):
  aws_security_group.alb ← depends on: aws_vpc.main
  aws_lb.main ← depends on: aws_security_group.alb, aws_subnet.public[*]
  aws_lb_target_group.main ← depends on: aws_vpc.main
  aws_lb_listener.http ← depends on: aws_lb.main, aws_lb_target_group.main

Level 1 (ECS prerequisites — can parallelize with NAT and ALB):
  aws_security_group.ecs ← depends on: aws_vpc.main, aws_security_group.alb
  aws_cloudwatch_log_group.ecs ← no VPC dependencies
  aws_ecs_cluster.main ← no VPC dependencies

Level 2 (ECS application — depends on everything above):
  aws_ecs_task_definition.main ← depends on: aws_iam_role.ecs_task_execution, aws_iam_role.ecs_task, aws_cloudwatch_log_group.ecs
  aws_ecs_service.main ← depends on: aws_ecs_cluster.main, aws_ecs_task_definition.main, aws_lb_target_group.main, aws_security_group.ecs, aws_subnet.private[*], (implicit: NAT GW for image pull)
```

**Note:** Terraform resolves this graph automatically. The levels above reflect the logical dependency order, not separate apply operations. A single `tofu apply` handles everything.

## Patterns to Follow

### Pattern 1: Naming Convention (match existing exactly)

**What:** Every AWS resource name uses `"${module.this.id}-<suffix>"` and tags merge `module.this.tags` with a `Name` key.

**Observed in:** `vpc.tf`, `iam-ecs.tf` — every resource follows this pattern.

**Example for new resources:**
```hcl
resource "aws_ecs_cluster" "main" {
  name = "${module.this.id}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = merge(
    module.this.tags,
    { Name = "${module.this.id}-cluster" }
  )
}
```

**Confidence:** HIGH — directly observed in existing code.

### Pattern 2: Singleton Resource Naming (`main`)

**What:** Use `main` as the Terraform local name for primary/singleton resources within a domain file.

**Observed in:** `aws_vpc.main`, `aws_internet_gateway.main` in `vpc.tf`.

**Apply to:** `aws_ecs_cluster.main`, `aws_lb.main`, `aws_nat_gateway.main`, `aws_ecs_service.main`, `aws_ecs_task_definition.main`.

**Confidence:** HIGH — directly observed pattern.

### Pattern 3: Count-based Multi-AZ (for route table associations)

**What:** Use `count = length(...)` for resources that need one per AZ.

**Observed in:** `aws_subnet.public[*]`, `aws_subnet.private[*]`, `aws_route_table_association.public[*]`.

**Apply to:** `aws_route_table_association.private` needs `count = length(aws_subnet.private)`.

**Confidence:** HIGH — directly observed pattern.

### Pattern 4: Security Group with Source SG Reference

**What:** For least-privilege inter-service communication, reference source security group ID instead of CIDR blocks.

**Apply to:** ECS SG ingress rule should reference `aws_security_group.alb.id` as source, not a CIDR.

```hcl
resource "aws_security_group" "ecs" {
  name        = "${module.this.id}-ecs-sg"
  description = "Security group for ECS tasks"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Container port from ALB"
    from_port       = 5678
    to_port         = 5678
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    module.this.tags,
    { Name = "${module.this.id}-ecs-sg" }
  )
}
```

**Confidence:** HIGH — standard AWS security group pattern, required by exercise spec ("allow traffic from ALB on container port").

### Pattern 5: ECS Task Definition with jsonencode

**What:** Use Terraform's `jsonencode()` for container definitions inline rather than external JSON files. Matches the existing `jsonencode()` usage in `iam-ecs.tf` for assume role policies.

```hcl
resource "aws_ecs_task_definition" "main" {
  family                   = "${module.this.id}-http-echo"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "http-echo"
      image     = "hashicorp/http-echo:latest"
      essential = true
      command   = ["-text=Hello from ECS!"]
      portMappings = [
        {
          containerPort = 5678
          protocol      = "tcp"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  tags = merge(
    module.this.tags,
    { Name = "${module.this.id}-http-echo" }
  )
}
```

**Confidence:** HIGH — `jsonencode()` pattern established in `iam-ecs.tf`, Fargate requires `awsvpc` network mode (verified), `http-echo` default port is 5678 (verified from Docker Hub docs).

### Pattern 6: ECS Service with Circuit Breaker and Health Check Grace Period

**What:** ECS Service with deployment circuit breaker + rollback, and a health check grace period to avoid false positives during startup.

```hcl
resource "aws_ecs_service" "main" {
  name            = "${module.this.id}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.main.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  health_check_grace_period_seconds = 60

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.main.arn
    container_name   = "http-echo"
    container_port   = 5678
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  tags = merge(
    module.this.tags,
    { Name = "${module.this.id}-service" }
  )
}
```

**Key details:**
- `assign_public_ip = false` — tasks are in private subnets, use NAT for egress
- `container_name` must match the `name` field in the container definition exactly
- `container_port` must match the `containerPort` in port mappings
- `health_check_grace_period_seconds` is required when a load_balancer block is present — prevents premature unhealthy marking during image pull + startup

**Confidence:** HIGH — verified from Terraform registry docs and multiple production references.

## Anti-Patterns to Avoid

### Anti-Pattern 1: Separate security-groups.tf file

**What:** Putting all security groups in a dedicated `security-groups.tf` file.

**Why bad:** Breaks the domain-based file splitting pattern. Security groups are logically part of their domain — the ALB SG belongs with ALB resources, the ECS SG belongs with ECS resources. Separating them creates cross-file reference tangles and makes it harder to understand each domain file in isolation.

**Instead:** Put ALB SG in `alb.tf`, ECS SG in `ecs.tf`. The STRUCTURE.md mentions this as an alternative ("or inline in ecs.tf"), and it aligns better with the existing pattern where `iam-ecs.tf` contains IAM resources specific to ECS.

### Anti-Pattern 2: Using variables for values that should be hardcoded

**What:** Creating variables for container port, image name, CPU/memory, etc.

**Why bad:** Over-engineering for an interview exercise. KISS principle from STEERING.md. These values are specific to Exercise 1 and will change in Exercise 2 anyway (different image, different port). Variables add indirection without reuse benefit.

**Instead:** Hardcode `5678`, `hashicorp/http-echo:latest`, `256` CPU, `512` memory directly in the resource blocks. The README explicitly states these values.

### Anti-Pattern 3: Creating NAT Gateway per AZ

**What:** One NAT GW + one EIP per availability zone (3 total).

**Why bad:** Costs ~$96/month vs ~$32/month for a single NAT. PROJECT.md explicitly marks this out of scope: "Multiple NAT Gateways per AZ — Cost optimization, single NAT is sufficient for interview."

**Instead:** Single NAT Gateway in first public subnet, single private route table shared by all private subnets.

### Anti-Pattern 4: Using `aws_security_group_rule` separate resources

**What:** Defining security group rules as separate `aws_security_group_rule` resources instead of inline `ingress`/`egress` blocks.

**Why bad for this project:** For a simple exercise with fixed rules, inline blocks are clearer and keep all SG logic in one resource block. Separate rule resources are useful when rules are dynamic or managed by multiple teams, but add unnecessary complexity here.

**Instead:** Use inline `ingress` and `egress` blocks within the `aws_security_group` resource.

### Anti-Pattern 5: Putting NAT Gateway in a new file

**What:** Creating a separate `nat.tf` file for the NAT Gateway.

**Why bad:** NAT Gateway is networking infrastructure — it belongs in `vpc.tf` alongside the VPC, subnets, IGW, and route tables. The existing scaffold groups all networking in `vpc.tf`. Adding the NAT GW there follows the established domain pattern.

**Instead:** Add `aws_eip.nat`, `aws_nat_gateway.main`, `aws_route_table.private`, and `aws_route_table_association.private` to `vpc.tf`.

## Build Order (Suggested Implementation Sequence)

Terraform handles the dependency graph automatically in a single `tofu apply`, but for **implementation order** (writing code), this sequence minimizes errors and allows incremental validation:

### Step 1: NAT Gateway in `vpc.tf`

**Why first:** Without NAT, ECS tasks in private subnets can't pull images from Docker Hub or send logs to CloudWatch. This is the most critical missing piece.

**Resources to add to `vpc.tf`:**
1. `aws_eip.nat`
2. `aws_nat_gateway.main` → depends on EIP + first public subnet
3. `aws_route_table.private` → depends on VPC + NAT GW
4. `aws_route_table_association.private[*]` → depends on private RT + private subnets

**Validate:** `tofu plan` should show 4 new resources (1 EIP + 1 NAT + 1 RT + 3 RT associations = 6 total). Can `tofu apply` independently.

### Step 2: ALB infrastructure in `alb.tf`

**Why second:** ALB has no dependency on NAT or ECS. Building it second allows validation of the load balancer independently before wiring up ECS.

**Resources in new `alb.tf`:**
1. `aws_security_group.alb` → depends on VPC
2. `aws_lb.main` → depends on ALB SG + public subnets
3. `aws_lb_target_group.main` → depends on VPC
4. `aws_lb_listener.http` → depends on ALB + target group

**Validate:** `tofu plan` shows 4 new resources. Can `tofu apply` — ALB will have no targets but will be accessible via DNS (returns 503).

### Step 3: ECS infrastructure in `ecs.tf`

**Why third:** Depends on both NAT (for image pull) and ALB (for target group registration).

**Resources in new `ecs.tf`:**
1. `aws_security_group.ecs` → depends on VPC + ALB SG
2. `aws_cloudwatch_log_group.ecs` → no dependencies
3. `aws_ecs_cluster.main` → no VPC dependencies
4. `aws_ecs_task_definition.main` → depends on IAM roles + CW log group
5. `aws_ecs_service.main` → depends on cluster + task def + target group + ECS SG + private subnets

**Validate:** `tofu plan` shows 5 new resources. After `tofu apply`, ECS tasks start, pull image via NAT, register with target group, ALB returns "Hello from ECS!" on port 80.

### Step 4: Outputs in `outputs.tf`

**Why last:** Outputs depend on resources existing. Add after all resources are defined.

**Outputs to add:**
1. `alb_dns_name` → `aws_lb.main.dns_name`
2. `ecs_cluster_name` → `aws_ecs_cluster.main.name`

**Validate:** `tofu output alb_dns_name` returns the ALB DNS. `curl http://<dns>` returns "Hello from ECS!".

## Scalability Considerations

| Concern | This Exercise | Exercise 2 (RDS) | Exercise 3 (HTTPS) |
|---------|---------------|-------------------|---------------------|
| ECS SG | Port 5678 from ALB SG | Add egress rule for port 5432 to RDS SG | No change |
| ALB SG | Port 80 from 0.0.0.0/0 | No change | Add port 443 ingress |
| ALB Listener | HTTP on 80, forward to TG | No change | Add HTTPS listener on 443 |
| Task Definition | http-echo:latest, port 5678 | Replace with pgweb:latest, port 8080 | No change |
| Target Group | Port 5678, health check `/` | Change port to 8080 | No change |
| NAT Gateway | Single NAT, works for all exercises | No change needed | No change needed |

**The architecture is designed for progressive extension** — Exercise 2 adds `rds.tf` and modifies `ecs.tf` task definition; Exercise 3 adds `route53.tf` and `acm.tf` and extends `alb.tf` with HTTPS listener.

## Sources

- Existing codebase: `vpc.tf`, `iam-ecs.tf`, `main.tf`, `context.tf`, `outputs.tf`, `variables.tf`, `terraform.tfvars` — **PRIMARY** (HIGH confidence)
- `STEERING.md` — IaC principles guide — **PRIMARY** (HIGH confidence)
- `README.md` — Exercise requirements and success criteria — **PRIMARY** (HIGH confidence)
- `.planning/PROJECT.md` — Project scope and constraints — **PRIMARY** (HIGH confidence)
- `.planning/codebase/ARCHITECTURE.md` — Existing architecture analysis — **PRIMARY** (HIGH confidence)
- `.planning/codebase/STRUCTURE.md` — File organization guidance — **PRIMARY** (HIGH confidence)
- Terraform Registry: `aws_lb_target_group` docs — target_type=ip for Fargate — **VERIFIED** (HIGH confidence)
- Terraform Registry: `aws_ecs_cluster` docs — Container Insights `setting` block — **VERIFIED** (HIGH confidence)
- Docker Hub: `hashicorp/http-echo` — default port 5678, `-text` flag — **VERIFIED** (HIGH confidence)
- AWS ECS docs: deployment circuit breaker with rollback — **VERIFIED** (HIGH confidence)
- AWS ECS docs: `awsvpc` network mode required for Fargate — **VERIFIED** (HIGH confidence)

---

*Architecture research: 2026-03-17*
