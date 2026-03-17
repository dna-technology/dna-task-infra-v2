# Domain Pitfalls — ECS Fargate + ALB Deployment

**Domain:** Terraform ECS Fargate + ALB on AWS
**Researched:** 2026-03-17

## Critical Pitfalls

Mistakes that cause `terraform apply` failures or unhealthy/unreachable services.

### Pitfall 1: Container Name Mismatch Between Task Definition and Service
**What goes wrong:** ECS service `load_balancer.container_name` doesn't match the `name` field in `container_definitions` JSON. Service creates successfully but targets never register as healthy.
**Why it happens:** Container definitions are JSON-encoded strings; the name is buried inside a `jsonencode()` block and easy to typo or diverge from the service block.
**Consequences:** ALB target group shows 0 healthy targets. Service keeps draining and re-creating tasks indefinitely. No clear error message.
**Prevention:** Use a `locals` block for container name and port, referenced by both task definition and service:
```hcl
locals {
  container_name = "http-echo"
  container_port = 5678
}
```
**Detection:** ALB target group health checks all failing; `ecs:DescribeServices` shows `runningCount = 0` with tasks cycling.

### Pitfall 2: Missing NAT Gateway for Private Subnet ECS Tasks
**What goes wrong:** ECS tasks in private subnets cannot pull container images or send logs to CloudWatch.
**Why it happens:** The scaffold README claims NAT Gateway is pre-created, but it is NOT in the Terraform code. Easy to assume it exists.
**Consequences:** Tasks fail with "CannotPullContainerError" or "ResourceInitializationError". Service never reaches steady state.
**Prevention:** Add NAT Gateway + EIP + private route table BEFORE ECS resources. Verify with `terraform plan` that the route table has a `0.0.0.0/0 → nat_gateway` route.
**Detection:** ECS service events show "CannotPullContainerError: pull image manifest has been retried N time(s)".

### Pitfall 3: Forgetting `depends_on` for NAT Gateway → Internet Gateway
**What goes wrong:** `terraform apply` creates NAT Gateway before Internet Gateway is fully attached to VPC.
**Why it happens:** Terraform can't infer this dependency from resource references alone (NAT GW references subnet, not IGW directly).
**Consequences:** NAT Gateway creation fails with an AWS API error.
**Prevention:** Explicit `depends_on = [aws_internet_gateway.main]` on `aws_nat_gateway.main`.
**Detection:** `terraform apply` fails during NAT Gateway creation.

### Pitfall 4: Using `target_type = "instance"` Instead of `"ip"` with Fargate
**What goes wrong:** Fargate tasks use `awsvpc` network mode, which assigns IPs to tasks directly. Instance-type target groups expect EC2 instance IDs.
**Why it happens:** Default `target_type` is `"instance"`. Easy to omit.
**Consequences:** ECS service fails to register targets with the target group. Error: "InvalidParameterException: The provided target group has a target type that is not valid for the specified ECS launch type."
**Prevention:** Always set `target_type = "ip"` on target groups used with Fargate.
**Detection:** Immediate error during `terraform apply` when creating ECS service.

### Pitfall 5: Missing `awslogs-stream-prefix` in Container Log Configuration
**What goes wrong:** Fargate tasks fail to start because the awslogs log driver requires stream prefix on Fargate.
**Why it happens:** The `awslogs-stream-prefix` option is only required on Fargate (not EC2 launch type). Easy to miss.
**Consequences:** Task fails to launch. Error in ECS service events.
**Prevention:** Always include `"awslogs-stream-prefix" = "app"` (or any string) in logConfiguration options.
**Detection:** ECS task fails to start; events show log driver configuration error.

## Moderate Pitfalls

### Pitfall 6: No `health_check_grace_period_seconds` on ECS Service
**What goes wrong:** ALB marks new task as unhealthy before it finishes starting, ECS replaces it, new task starts, gets killed again → infinite loop.
**Why it happens:** Fargate tasks take time to pull image and start container. Default grace period is 0, meaning health checks begin immediately.
**Prevention:** Set `health_check_grace_period_seconds = 60` on `aws_ecs_service`. 60s is generous for http-echo but safe.
**Detection:** Tasks cycling continuously with health check failures in ALB target group.

### Pitfall 7: ECS Service Created Before ALB Listener Exists
**What goes wrong:** ECS tries to register with target group before listener is attached to ALB, causing a race condition.
**Why it happens:** Terraform may not always infer the full dependency chain from service → target group → listener → ALB.
**Prevention:** Add `depends_on = [aws_lb_listener.http]` on `aws_ecs_service.app`.
**Detection:** Intermittent `terraform apply` failures or ECS service creation errors.

### Pitfall 8: Using `vpc = true` on `aws_eip` with Provider ~> 5.0
**What goes wrong:** `terraform plan` fails with deprecation/removal error.
**Why it happens:** `vpc = true` was the old way to create VPC EIPs. Removed in AWS provider 5.0.
**Prevention:** Use `domain = "vpc"` instead of `vpc = true`.
**Detection:** Immediate `terraform plan` error.

### Pitfall 9: Security Group Inline Rules Mixed with Separate Rule Resources
**What goes wrong:** Terraform enters an infinite loop of adding/removing rules, or rules get silently overwritten.
**Why it happens:** Using `ingress {}` blocks inside `aws_security_group` AND `aws_vpc_security_group_ingress_rule` resources on the same SG.
**Prevention:** Choose one approach and stick with it. Recommended: separate rule resources only. Do NOT mix.
**Detection:** `terraform plan` shows changes on every run even after successful apply.

### Pitfall 10: CPU/Memory Passed as Numbers Instead of Strings
**What goes wrong:** Task definition may fail validation or behave unexpectedly.
**Why it happens:** CPU "256" and memory "512" look like numbers, but the Terraform resource expects strings for Fargate.
**Prevention:** Always quote: `cpu = "256"`, `memory = "512"`.
**Detection:** `terraform plan` may succeed but `apply` fails with InvalidParameterException about CPU/memory combination.

## Minor Pitfalls

### Pitfall 11: ALB Name Exceeds 32-Character Limit
**What goes wrong:** `terraform apply` fails on ALB creation.
**Why it happens:** ALB names have a 32-character limit. Long module.this.id + suffix can exceed it.
**Prevention:** Verify: `dna-interview-ecs-alb` = 21 chars. Safe. But be aware for future naming.
**Detection:** Immediate apply error.

### Pitfall 12: Forgetting to Add Container `command` for http-echo
**What goes wrong:** http-echo starts with default empty text, returning an empty HTTP response.
**Why it happens:** http-echo requires `-text=` flag to set response body. Without it, response is empty string.
**Prevention:** Set `command = ["-text=Hello from ECS!"]` in container definition.
**Detection:** `curl http://<alb-dns>` returns empty or default response.

### Pitfall 13: Tag Duplication with Provider `default_tags`
**What goes wrong:** Tags defined on resources that overlap with provider `default_tags` cause "tag already exists" warnings or perpetual diffs.
**Why it happens:** `main.tf` sets `default_tags { tags = module.this.tags }` on the provider. Resources also set `tags = merge(module.this.tags, {...})`.
**Prevention:** In resources, only add the `Name` tag in the `tags` block. The other tags (namespace, environment, etc.) come from provider default_tags automatically. Alternatively, accept the merge behavior — it works but may show warnings.
**Detection:** `terraform plan` shows tag changes on every run.

## Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation |
|-------------|---------------|------------|
| NAT Gateway | Missing depends_on on IGW | Add explicit `depends_on = [aws_internet_gateway.main]` |
| ECS Task Definition | Container port/name mismatch with service | Use locals for shared values |
| ECS Service | No health check grace period | Set `health_check_grace_period_seconds = 60` |
| ALB Target Group | Wrong target_type for Fargate | Always use `target_type = "ip"` |
| Security Groups | Mixing inline and separate rules | Use only separate rule resources |
| CloudWatch Logs | Relying on auto-creation | Create log group in Terraform, not via `awslogs-create-group` |

## Sources

- Terraform AWS provider registry documentation (resource reference pages)
- AWS ECS Developer Guide — Fargate task networking, awslogs driver requirements
- Community sources: Stack Overflow, HashiCorp Discuss, dev.to guides
- Interview candidate policy JSON — IAM constraint verification
- Multiple implementation guides confirming patterns (2025-2026)

---

*Pitfalls research: 2026-03-17*
