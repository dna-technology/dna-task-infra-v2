# Technology Stack — ECS Fargate + ALB Resources

**Project:** DNA Interview Infrastructure — Exercise 1
**Researched:** 2026-03-17
**Scope:** Terraform AWS resource types, arguments, and configurations for ECS Fargate + ALB deployment on existing VPC scaffold
**Overall confidence:** HIGH — All resource types verified against AWS provider ~> 5.0 registry docs and multiple implementation sources

## Existing Stack (DO NOT modify — validated)

| Resource | File | Reference |
|----------|------|-----------|
| `aws_vpc.main` | `vpc.tf` | `aws_vpc.main.id` |
| `aws_internet_gateway.main` | `vpc.tf` | `aws_internet_gateway.main.id` |
| `aws_subnet.public[*]` (count=3) | `vpc.tf` | `aws_subnet.public[*].id` |
| `aws_subnet.private[*]` (count=3) | `vpc.tf` | `aws_subnet.private[*].id` |
| `aws_route_table.public` | `vpc.tf` | Already has 0.0.0.0/0 → IGW route |
| `aws_route_table_association.public[*]` | `vpc.tf` | Public subnets associated |
| `aws_iam_role.ecs_task_execution` | `iam-ecs.tf` | Execution role with AmazonECSTaskExecutionRolePolicy |
| `aws_iam_role.ecs_task` | `iam-ecs.tf` | Task role (no policies attached yet) |
| `module.this` | `context.tf` | CloudPosse null-label → `module.this.id` = `dna-interview-ecs` |
| Provider `default_tags` | `main.tf` | `tags = module.this.tags` on provider block |

## New Resources Required

### 1. NAT Gateway (for private subnet egress)

**File:** `vpc.tf` (extends existing networking)

#### `aws_eip.nat`
```hcl
resource "aws_eip" "nat" {
  domain = "vpc"    # REQUIRED: replaces deprecated `vpc = true` (removed in provider 5.x)

  tags = merge(
    module.this.tags,
    { Name = "${module.this.id}-nat-eip" }
  )
}
```
**Key arguments:**
| Argument | Value | Why |
|----------|-------|-----|
| `domain` | `"vpc"` | **Must use `domain = "vpc"`** — the old `vpc = true` argument was removed in AWS provider 5.0. HIGH confidence (registry docs). |

#### `aws_nat_gateway.main`
```hcl
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id    # Must be in a PUBLIC subnet

  tags = merge(
    module.this.tags,
    { Name = "${module.this.id}-nat" }
  )

  depends_on = [aws_internet_gateway.main]   # Explicit dependency — AWS requires IGW to exist first
}
```
**Key arguments:**
| Argument | Value | Why |
|----------|-------|-----|
| `allocation_id` | EIP id | Associates the Elastic IP with NAT GW |
| `subnet_id` | `aws_subnet.public[0].id` | NAT Gateway MUST be in a public subnet |
| `depends_on` | `[aws_internet_gateway.main]` | **Critical:** Terraform can't infer this dependency; NAT GW creation fails without IGW. Verified in Terraform docs and multiple sources. |

**Cost note:** Single NAT Gateway (~$32/month + $0.045/GB data processing). Per-AZ NAT is unnecessary for interview exercise. Explicitly out of scope per PROJECT.md.

#### `aws_route_table.private`
```hcl
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
```

#### `aws_route_table_association.private`
```hcl
resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
```
**Pattern:** Single route table shared by all private subnets (matches single NAT GW decision). Uses `count` to match existing scaffold pattern in `vpc.tf`.

---

### 2. ECS Cluster

**File:** `ecs.tf` (new file — separate concern per STEERING.md)

#### `aws_ecs_cluster.main`
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
**Key arguments:**
| Argument | Value | Why |
|----------|-------|-----|
| `name` | `"${module.this.id}-cluster"` | Follows STEERING.md naming convention |
| `setting.containerInsights` | `"enabled"` | Use `"enabled"` not `"enhanced"`. Enhanced requires provider >= 5.81.0 and is overkill for interview. `"enabled"` gives standard Container Insights metrics (CPU, memory, network). HIGH confidence (registry docs). |

**NOT adding:** `aws_ecs_cluster_capacity_providers` — Not needed. The ECS service specifies `launch_type = "FARGATE"` directly, which is simpler than capacity provider strategies for a single-service cluster. Capacity providers are for mixed Fargate/Fargate Spot or EC2 strategies.

---

### 3. CloudWatch Log Group

**File:** `ecs.tf` (co-located with ECS resources)

#### `aws_cloudwatch_log_group.ecs`
```hcl
resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${module.this.id}"
  retention_in_days = 30

  tags = merge(
    module.this.tags,
    { Name = "${module.this.id}-ecs-logs" }
  )
}
```
**Key arguments:**
| Argument | Value | Why |
|----------|-------|-----|
| `name` | `"/ecs/${module.this.id}"` | Convention: `/ecs/<app-name>` is standard CloudWatch log group naming for ECS. Results in `/ecs/dna-interview-ecs`. |
| `retention_in_days` | `30` | Valid values: 1, 3, 5, 7, 14, 30, 60, 90, etc. 30 days balances cost and debuggability for interview context. Default (`0`) means infinite retention — never use default. |

**Important:** Create the log group in Terraform BEFORE the task definition references it. Do NOT rely on `awslogs-create-group = "true"` — that requires additional IAM permissions and creates unmanaged resources.

---

### 4. ECS Task Definition

**File:** `ecs.tf`

#### `aws_ecs_task_definition.app`
```hcl
resource "aws_ecs_task_definition" "app" {
  family                   = "${module.this.id}-app"
  network_mode             = "awsvpc"          # REQUIRED for Fargate
  requires_compatibilities = ["FARGATE"]       # REQUIRED for Fargate
  cpu                      = "256"             # Smallest: 0.25 vCPU
  memory                   = "512"             # Valid with 256 CPU: 512, 1024, 2048
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "http-echo"
      image     = "hashicorp/http-echo:latest"
      essential = true
      
      portMappings = [
        {
          containerPort = 5678        # http-echo default port
          protocol      = "tcp"
        }
      ]
      
      command = ["-text=Hello from ECS!"]
      
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/${module.this.id}"
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "app"
        }
      }
    }
  ])

  tags = merge(
    module.this.tags,
    { Name = "${module.this.id}-task" }
  )
}
```

**Key arguments explained:**

| Argument | Value | Why |
|----------|-------|-----|
| `family` | `"${module.this.id}-app"` | Groups task definition revisions. Results in `dna-interview-ecs-app`. |
| `network_mode` | `"awsvpc"` | **REQUIRED for Fargate** — each task gets its own ENI. No other option works. |
| `requires_compatibilities` | `["FARGATE"]` | Validates the task def is Fargate-compatible at creation time. |
| `cpu` | `"256"` | 0.25 vCPU — smallest Fargate size. **Must be string.** Valid: "256", "512", "1024", "2048", "4096". |
| `memory` | `"512"` | 512 MiB — smallest valid with 256 CPU. **Must be string.** Valid with 256 CPU: "512", "1024", "2048". |
| `execution_role_arn` | existing role | ECS agent uses this to pull images + write logs. Already in `iam-ecs.tf`. |
| `task_role_arn` | existing role | App permissions. Already in `iam-ecs.tf`. Not strictly needed for http-echo but best practice. |

**Container definition fields:**

| Field | Value | Why |
|-------|-------|-----|
| `name` | `"http-echo"` | Must match `container_name` in ECS service `load_balancer` block. |
| `image` | `"hashicorp/http-echo:latest"` | Per interview requirements. Default port 5678, serves text response. |
| `essential` | `true` | Task stops if this container exits. |
| `containerPort` | `5678` | http-echo default listening port (confirmed from Docker Hub + GitHub README). |
| `command` | `["-text=Hello from ECS!"]` | http-echo accepts `-text` flag to set response body. |
| `logDriver` | `"awslogs"` | CloudWatch Logs driver — built into Fargate, no sidecar needed. |
| `awslogs-stream-prefix` | `"app"` | **REQUIRED for Fargate** with awslogs driver. Stream name format: `prefix/container-name/task-id`. |

**Fargate CPU/Memory valid combinations (smallest relevant):**

| CPU (units) | Memory (MiB) options |
|-------------|---------------------|
| 256 (0.25 vCPU) | 512, 1024, 2048 |
| 512 (0.5 vCPU) | 1024, 2048, 3072, 4096 |
| 1024 (1 vCPU) | 2048, 3072, 4096, 5120, 6144, 7168, 8192 |

**Use 256/512 — smallest possible.** http-echo is a ~5MB Go binary, needs virtually no resources.

---

### 5. ECS Service

**File:** `ecs.tf`

#### `aws_ecs_service.app`
```hcl
resource "aws_ecs_service" "app" {
  name            = "${module.this.id}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false    # Private subnets — NAT handles egress
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "http-echo"      # Must match container_definitions name
    container_port   = 5678             # Must match containerPort
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  health_check_grace_period_seconds = 60

  tags = merge(
    module.this.tags,
    { Name = "${module.this.id}-service" }
  )

  depends_on = [aws_lb_listener.http]
}
```

**Key arguments explained:**

| Argument | Value | Why |
|----------|-------|-----|
| `launch_type` | `"FARGATE"` | Simpler than capacity provider strategy for single-service setup. |
| `desired_count` | `1` | Minimum for interview. No auto-scaling needed. |
| `subnets` | `aws_subnet.private[*].id` | ECS tasks in private subnets (security best practice per README). |
| `assign_public_ip` | `false` | Private subnets use NAT for egress — no public IP needed. |
| `security_groups` | `[aws_security_group.ecs.id]` | Restrict traffic to ALB-only ingress. |
| `container_name` | `"http-echo"` | **Must exactly match** the `name` in container_definitions JSON. |
| `container_port` | `5678` | **Must exactly match** the `containerPort` in container_definitions. |
| `deployment_circuit_breaker.enable` | `true` | Auto-rolls back failed deployments. Per PROJECT.md requirements. |
| `deployment_circuit_breaker.rollback` | `true` | Enables automatic rollback on circuit breaker trigger. |
| `health_check_grace_period_seconds` | `60` | **Critical:** Gives container time to start before ALB health checks mark it unhealthy. Without this, Fargate tasks can get killed before they're ready. 60s is generous for http-echo (starts in <1s) but prevents race conditions. |
| `depends_on` | `[aws_lb_listener.http]` | **Important:** Prevents race condition where ECS tries to register targets before ALB listener exists. |

**NOT adding:**
- `platform_version` — Defaults to `"LATEST"` which is correct. Pinning to a specific version is only needed for reproducibility in production.
- `deployment_maximum_percent` / `deployment_minimum_healthy_percent` — Defaults (200%/100%) are fine for `desired_count = 1`.
- `enable_execute_command` — Not needed for interview. Would require additional IAM permissions.
- `lifecycle { ignore_changes = [desired_count] }` — Only needed with auto-scaling, which we're not using.

---

### 6. Application Load Balancer

**File:** `alb.tf` (new file — separate concern)

#### `aws_lb.app`
```hcl
resource "aws_lb" "app" {
  name               = "${module.this.id}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  tags = merge(
    module.this.tags,
    { Name = "${module.this.id}-alb" }
  )
}
```
**Key arguments:**
| Argument | Value | Why |
|----------|-------|-----|
| `name` | `"${module.this.id}-alb"` | ALB names have 32-char limit. `dna-interview-ecs-alb` = 21 chars. Fine. |
| `internal` | `false` | Internet-facing ALB. |
| `load_balancer_type` | `"application"` | ALB, not NLB. Required for HTTP path/host routing. |
| `subnets` | `aws_subnet.public[*].id` | ALB must be in public subnets (at least 2 AZs). We have 3. |

**NOT adding:**
- `enable_deletion_protection` — Not needed for interview (would block `terraform destroy`).
- `access_logs` — Over-engineering for interview scope.
- `drop_invalid_header_fields` — Good security practice but not required.
- `idle_timeout` — Default 60s is fine.

#### `aws_lb_target_group.app`
```hcl
resource "aws_lb_target_group" "app" {
  name        = "${module.this.id}-tg"
  port        = 5678
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"           # REQUIRED for Fargate awsvpc networking

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    port                = "traffic-port"
  }

  tags = merge(
    module.this.tags,
    { Name = "${module.this.id}-tg" }
  )
}
```
**Key arguments:**
| Argument | Value | Why |
|----------|-------|-----|
| `target_type` | `"ip"` | **REQUIRED for Fargate.** Fargate uses `awsvpc` networking where each task gets its own IP. Cannot use `"instance"`. HIGH confidence. |
| `port` | `5678` | Default port for target registration. Must match container port. |
| `protocol` | `"HTTP"` | http-echo serves plain HTTP. |
| `health_check.path` | `"/"` | http-echo responds on `/` with the configured text. |
| `health_check.matcher` | `"200"` | http-echo returns 200 on `/`. |
| `health_check.port` | `"traffic-port"` | Check on the same port as traffic (5678). |
| `health_check.healthy_threshold` | `2` | 2 consecutive successes → healthy. Faster registration. |
| `health_check.unhealthy_threshold` | `3` | 3 consecutive failures → unhealthy. Avoids flapping. |
| `health_check.interval` | `30` | Check every 30s. Default, works fine. |
| `health_check.timeout` | `5` | Must be less than interval. |

**Do NOT add:** `aws_lb_target_group_attachment` — ECS service manages target registration automatically via the `load_balancer` block. Adding manual attachments conflicts with ECS management.

#### `aws_lb_listener.http`
```hcl
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }

  tags = merge(
    module.this.tags,
    { Name = "${module.this.id}-http-listener" }
  )
}
```
**Key arguments:**
| Argument | Value | Why |
|----------|-------|-----|
| `port` | `80` | Standard HTTP port. Users hit `http://<alb-dns>:80`. |
| `protocol` | `"HTTP"` | No HTTPS for Exercise 1 (Exercise 3 adds TLS). |
| `default_action.type` | `"forward"` | Send all traffic to target group. |

---

### 7. Security Groups

**File:** `security-groups.tf` (new file — separate concern, reusable for Exercises 2 & 3)

**Best practice:** Use `aws_vpc_security_group_ingress_rule` / `aws_vpc_security_group_egress_rule` (separate rule resources) instead of inline `ingress`/`egress` blocks. This is the current recommendation from the AWS provider docs (verified). Avoids rule conflicts and gives granular control.

**However — KISS consideration for interview:** The existing scaffold uses simple patterns. Using inline rules or the older `aws_security_group_rule` resource is also acceptable and arguably more readable for an interview context. The critical thing is NOT to mix inline and separate rule resources on the same security group.

**Recommended approach:** Use separate `aws_vpc_security_group_ingress_rule`/`aws_vpc_security_group_egress_rule` resources — it's the provider-recommended best practice and demonstrates current knowledge.

#### `aws_security_group.alb`
```hcl
resource "aws_security_group" "alb" {
  name        = "${module.this.id}-alb-sg"
  description = "Security group for ALB - allows HTTP from internet"
  vpc_id      = aws_vpc.main.id

  tags = merge(
    module.this.tags,
    { Name = "${module.this.id}-alb-sg" }
  )
}
```

#### ALB Security Group Rules
```hcl
resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "Allow HTTP from internet"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "alb_all" {
  security_group_id = aws_security_group.alb.id
  description       = "Allow all outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
```

#### `aws_security_group.ecs`
```hcl
resource "aws_security_group" "ecs" {
  name        = "${module.this.id}-ecs-sg"
  description = "Security group for ECS tasks - allows traffic from ALB only"
  vpc_id      = aws_vpc.main.id

  tags = merge(
    module.this.tags,
    { Name = "${module.this.id}-ecs-sg" }
  )
}
```

#### ECS Security Group Rules
```hcl
resource "aws_vpc_security_group_ingress_rule" "ecs_from_alb" {
  security_group_id            = aws_security_group.ecs.id
  description                  = "Allow container port from ALB"
  ip_protocol                  = "tcp"
  from_port                    = 5678
  to_port                      = 5678
  referenced_security_group_id = aws_security_group.alb.id    # SG-to-SG reference
}

resource "aws_vpc_security_group_egress_rule" "ecs_all" {
  security_group_id = aws_security_group.ecs.id
  description       = "Allow all outbound (needed for ECR image pull and CloudWatch logs)"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
```

**Security group design rationale:**
| Rule | Why |
|------|-----|
| ALB ingress: 80 from 0.0.0.0/0 | Internet-facing HTTP only. No 443 yet (Exercise 3). |
| ALB egress: all outbound | ALB needs to reach ECS tasks on 5678. |
| ECS ingress: 5678 from ALB SG only | **Least privilege** — only ALB can reach container port. Uses SG-to-SG reference, not CIDR. |
| ECS egress: all outbound | Needed for: (1) pulling container image from Docker Hub via NAT, (2) sending logs to CloudWatch, (3) ECS agent communication. |

**NOT adding:** VPC endpoints for ECR/CloudWatch. Would eliminate some NAT traffic costs but is over-engineering for interview scope.

---

### 8. Outputs

**File:** `outputs.tf` (extend existing)

```hcl
output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.app.dns_name
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  description = "Name of the ECS service"
  value       = aws_ecs_service.app.name
}
```

---

## File Organization

| New File | Contents | Rationale |
|----------|----------|-----------|
| `ecs.tf` | Cluster, task definition, service, log group | ECS is one domain concern |
| `alb.tf` | ALB, target group, listener | Load balancing is a separate concern |
| `security-groups.tf` | Both security groups + all rules | Security is a cross-cutting concern; co-locating SG rules makes them auditable |

**Extended files:**
| File | Additions |
|------|-----------|
| `vpc.tf` | EIP, NAT Gateway, private route table + associations |
| `outputs.tf` | ALB DNS name, ECS cluster name, ECS service name |

This follows STEERING.md principle #6 (Modularity) and matches the scaffold's domain-based splitting pattern (`vpc.tf`, `iam-ecs.tf`).

---

## Complete Resource Inventory

| # | Resource Type | Logical Name | Purpose |
|---|---------------|--------------|---------|
| 1 | `aws_eip` | `nat` | Elastic IP for NAT Gateway |
| 2 | `aws_nat_gateway` | `main` | Private subnet internet egress |
| 3 | `aws_route_table` | `private` | Routes private subnet traffic to NAT |
| 4 | `aws_route_table_association` | `private[0..2]` | Associates 3 private subnets |
| 5 | `aws_ecs_cluster` | `main` | ECS cluster with Container Insights |
| 6 | `aws_cloudwatch_log_group` | `ecs` | Container log storage |
| 7 | `aws_ecs_task_definition` | `app` | Fargate task for http-echo |
| 8 | `aws_ecs_service` | `app` | Manages running tasks |
| 9 | `aws_lb` | `app` | Application Load Balancer |
| 10 | `aws_lb_target_group` | `app` | IP-type target group for Fargate |
| 11 | `aws_lb_listener` | `http` | HTTP:80 listener |
| 12 | `aws_security_group` | `alb` | ALB security group |
| 13 | `aws_security_group` | `ecs` | ECS tasks security group |
| 14 | `aws_vpc_security_group_ingress_rule` | `alb_http` | ALB HTTP ingress |
| 15 | `aws_vpc_security_group_egress_rule` | `alb_all` | ALB egress |
| 16 | `aws_vpc_security_group_ingress_rule` | `ecs_from_alb` | ECS ingress from ALB |
| 17 | `aws_vpc_security_group_egress_rule` | `ecs_all` | ECS egress |

**Total: 17 new resources** (14 unique resource types, 3 counted instances for route table associations)

---

## IAM Constraint Verification

The interview candidate policy (`setup/interview-candidate-policy.json`) was verified against all new resources:

| Resource Type | Required IAM Action | Policy Sid | Status |
|---------------|-------------------|------------|--------|
| `aws_eip` | `ec2:AllocateAddress` | `VPCNetworking` | ✅ Allowed |
| `aws_nat_gateway` | `ec2:CreateNatGateway` | `VPCNetworking` | ✅ Allowed |
| `aws_route_table` | `ec2:CreateRouteTable` | `VPCNetworking` | ✅ Allowed |
| `aws_ecs_cluster` | `ecs:CreateCluster` | `ECSManagement` | ✅ Allowed |
| `aws_ecs_task_definition` | `ecs:RegisterTaskDefinition` | `ECSManagement` | ✅ Allowed |
| `aws_ecs_service` | `ecs:CreateService` | `ECSManagement` | ✅ Allowed |
| `aws_lb` | `elasticloadbalancing:CreateLoadBalancer` | `ALBManagement` | ✅ Allowed |
| `aws_lb_target_group` | `elasticloadbalancing:CreateTargetGroup` | `ALBManagement` | ✅ Allowed |
| `aws_lb_listener` | `elasticloadbalancing:CreateListener` | `ALBManagement` | ✅ Allowed |
| `aws_security_group` | `ec2:CreateSecurityGroup` | `SecurityGroups` | ✅ Allowed |
| `aws_vpc_security_group_*_rule` | `ec2:AuthorizeSecurityGroup*` | `SecurityGroups` | ✅ Allowed |
| `aws_cloudwatch_log_group` | `logs:CreateLogGroup` | `CloudWatchLogs` | ✅ Allowed |
| IAM role creation | `iam:CreateRole` | `DenyDangerousActions` | ❌ **DENIED** — Roles must be pre-existing |
| IAM policy attachment | `iam:AttachRolePolicy` | `DenyDangerousActions` | ❌ **DENIED** — Pre-existing only |

**Critical IAM note:** The `DenyDangerousActions` statement blocks `iam:CreateRole`, `iam:DeleteRole`, `iam:AttachRolePolicy`, `iam:DetachRolePolicy`, and `iam:PutRolePolicy`. The existing roles in `iam-ecs.tf` CANNOT be created or modified by the interview candidate at runtime. They must already exist in the AWS account, OR the scaffold was applied by an admin first. **Do not add any new IAM resources.**

---

## What NOT to Add (Anti-Over-Engineering)

| Temptation | Why Skip |
|------------|----------|
| `aws_ecs_cluster_capacity_providers` | Only needed for mixed Fargate/Spot. `launch_type = "FARGATE"` on service is simpler. |
| Auto-scaling (`aws_appautoscaling_*`) | Single task, interview scope. |
| Multiple NAT Gateways | Explicitly out of scope. Single NAT is sufficient. |
| HTTPS listener / ACM certificate | Exercise 3 scope. |
| VPC endpoints (S3, ECR, CloudWatch) | Cost optimization, not needed for interview. |
| Service discovery / Cloud Map | Single service, no service-to-service communication. |
| ECS Exec (`enable_execute_command`) | Debugging tool, needs additional IAM permissions which are denied. |
| WAF / Shield | Not in scope. |
| Access logging for ALB | Not in scope. |
| Container health check in task def | ALB health check is sufficient. Adding container-level health check adds complexity without value for http-echo. |
| `aws_lb_target_group.deregistration_delay` | Default 300s is fine. Could reduce to 30s but not important. |
| `platform_version` on ECS service | `"LATEST"` default is correct and always picks the current stable version. |

---

## Confidence Assessment

| Area | Confidence | Basis |
|------|------------|-------|
| Resource types | HIGH | Terraform registry docs + multiple verified implementation guides |
| Resource arguments | HIGH | Cross-referenced with AWS provider 5.x registry, multiple sources agree |
| `domain = "vpc"` for EIP | HIGH | `vpc = true` was deprecated/removed in provider 5.0, verified |
| `containerInsights = "enabled"` | HIGH | Registry docs; `"enhanced"` available in 5.81.0+ but not needed |
| `target_type = "ip"` for Fargate | HIGH | Mandatory for awsvpc network mode, universally documented |
| `awslogs-stream-prefix` required for Fargate | HIGH | AWS docs explicitly state this is required |
| Security group rule resources | HIGH | AWS provider docs recommend `aws_vpc_security_group_*_rule` over inline |
| `depends_on` for NAT→IGW | HIGH | Terraform docs + AWS API requirement |
| `depends_on` for ECS Service→Listener | MEDIUM | Common best practice but Terraform may infer this via target_group_arn chain |
| IAM policy constraints | HIGH | Directly verified from `interview-candidate-policy.json` |
| http-echo port 5678 | HIGH | Docker Hub docs + GitHub README confirm default port |
| CPU/Memory "256"/"512" as strings | HIGH | Terraform registry docs specify string type for Fargate |

---

## Sources

- AWS Provider Registry: `aws_ecs_cluster`, `aws_ecs_service`, `aws_ecs_task_definition`, `aws_lb`, `aws_lb_target_group`, `aws_lb_listener`, `aws_security_group`, `aws_vpc_security_group_ingress_rule` — registry.terraform.io
- hashicorp/http-echo Docker Hub + GitHub README — port 5678, `-text` flag
- AWS ECS Developer Guide — awslogs driver, Fargate platform versions
- AWS CloudWatch docs — Container Insights setup, `"enhanced"` vs `"enabled"` values
- hashicorp/terraform-provider-aws PR #40456 — `enhanced` containerInsights added in v5.81.0
- Oneuptime blog series (2026-02) — ECS + ALB + NAT Gateway Terraform patterns
- interview-candidate-policy.json — IAM constraint verification

---

*Stack research: 2026-03-17*
