# Feature Landscape

**Domain:** ECS Fargate service behind ALB on existing VPC scaffold
**Researched:** 2026-03-17
**Milestone:** v1.0 ECS + ALB

## Table Stakes

Features that are **required** for a functional ECS Fargate + ALB deployment. Missing any of these = deployment broken or unreachable.

### Networking Prerequisites

| Feature | Why Expected | Complexity | Dependencies | Notes |
|---------|-------------|------------|--------------|-------|
| NAT Gateway (single AZ) | Fargate tasks in private subnets need internet egress to pull container images from Docker Hub. Without NAT, tasks fail to start with image pull errors. | Low | `aws_subnet.public[0]`, `aws_internet_gateway.main` | Requires Elastic IP allocation first. Must be in a **public** subnet. Single NAT is a conscious cost trade-off (documented in PROJECT.md). |
| Elastic IP for NAT | NAT Gateway requires a static public IP for outbound traffic translation. | Low | None | `domain = "vpc"` (the old `vpc = true` is deprecated). Add `depends_on = [aws_internet_gateway.main]` per AWS docs — NAT needs IGW to exist first. |
| Private subnet route table | Private subnets currently have no route to internet. Must create route table with `0.0.0.0/0 → nat_gateway_id` and associate with all 3 private subnets. | Low | NAT Gateway | Scaffold only created a **public** route table (`aws_route_table.public`). Private subnets have no route table associations — this is the gap the README incorrectly claims is already handled. |

### ECS Cluster

| Feature | Why Expected | Complexity | Dependencies | Notes |
|---------|-------------|------------|--------------|-------|
| ECS Cluster with Fargate | The container orchestration control plane. Required for any ECS service. | Low | None | Simple resource — just a name and settings block. No capacity providers needed since Fargate is the default. |
| Container Insights enabled | README explicitly requires this. Provides cluster/service/task-level CPU, memory, network metrics and automated dashboards. | Low | None | `setting { name = "containerInsights"; value = "enabled" }`. Use `"enabled"` (standard), not `"enhanced"` — enhanced requires AWS provider >= 5.81.0 and adds cost. Standard is sufficient for an interview exercise. |

### ECS Task Definition

| Feature | Why Expected | Complexity | Dependencies | Notes |
|---------|-------------|------------|--------------|-------|
| Task definition with `hashicorp/http-echo` | Defines the container image, port, CPU/memory, and logging config. The blueprint for what ECS runs. | Medium | IAM roles (existing), CloudWatch log group | Image: `hashicorp/http-echo:latest`. **Must pass** `-text="Hello from ECS!"` as command args and `-listen=:5678` (default port). Network mode **must** be `awsvpc` (only mode Fargate supports). |
| CPU/Memory allocation (256/512) | Fargate requires explicit CPU/memory at task level from a fixed set of valid combinations. README recommends 256 CPU units / 512 MiB. | Low | None | Smallest Fargate size = 256 CPU / 512 MiB. Valid combo per AWS docs. Set `requires_compatibilities = ["FARGATE"]`. |
| Container port mapping (5678) | http-echo listens on port 5678 by default. Port must be exposed for ALB health checks and traffic routing. | Low | None | In `awsvpc` mode, `hostPort` must equal `containerPort`. Set both to `5678`. Protocol `tcp`. |
| CloudWatch logging configuration | Container logs must go to CloudWatch for debugging. Task execution role already has the managed policy that grants `logs:CreateLogStream` and `logs:PutLogEvents`. | Low | CloudWatch Log Group, task execution role (existing) | Use `awslogs` log driver. Set `awslogs-group`, `awslogs-region` (`eu-west-1`), and `awslogs-stream-prefix` (e.g., `ecs`). |
| Task execution role reference | Links to existing `aws_iam_role.ecs_task_execution` for image pulling and log writing. | Low | `iam-ecs.tf` (existing) | `execution_role_arn = aws_iam_role.ecs_task_execution.arn` |
| Task role reference | Links to existing `aws_iam_role.ecs_task` for application-level AWS API access. | Low | `iam-ecs.tf` (existing) | `task_role_arn = aws_iam_role.ecs_task.arn`. http-echo doesn't need AWS access, but best practice to always set it. |

### ECS Service

| Feature | Why Expected | Complexity | Dependencies | Notes |
|---------|-------------|------------|--------------|-------|
| ECS Service (Fargate, desired count 1) | Manages the lifecycle of running tasks — starts, stops, replaces on failure, connects to load balancer. | Medium | Cluster, task definition, target group, private subnets, ECS security group | `launch_type = "FARGATE"`. `desired_count = 1` sufficient for interview. Deploy in **private** subnets per security requirements. |
| awsvpc network configuration | Fargate requires explicit subnet and security group assignment via `network_configuration` block. | Low | Private subnets (existing), ECS security group | `subnets = aws_subnet.private[*].id`, `security_groups = [aws_security_group.ecs.id]`. **Do NOT** set `assign_public_ip = true` — tasks are in private subnets with NAT. |
| Load balancer integration | Connects ECS tasks to ALB target group so traffic routes to running containers. | Low | Target group, task definition container name/port | `load_balancer { target_group_arn, container_name = "http-echo", container_port = 5678 }`. Container name must **exactly** match the `name` field in the task definition's container definition. |
| Deployment circuit breaker with rollback | README explicitly requires this. Auto-detects failed deployments and rolls back to last working version. | Low | None | `deployment_circuit_breaker { enable = true, rollback = true }`. Essential safety net — without it, a bad deploy leaves the service stuck. |
| Health check grace period | Gives new tasks time to start and register with ALB before health checks count as failures. Without this, tasks may be killed before they're ready. | Low | None | `health_check_grace_period_seconds = 60`. http-echo starts almost instantly, but 60s accounts for image pull + ENI attachment + ALB registration. |

### Application Load Balancer

| Feature | Why Expected | Complexity | Dependencies | Notes |
|---------|-------------|------------|--------------|-------|
| ALB in public subnets | Internet-facing entry point for HTTP traffic. Must be in public subnets to be accessible from the internet. | Low | Public subnets (existing), ALB security group | `internal = false`, `load_balancer_type = "application"`. Requires **minimum 2** subnets in different AZs (we have 3). |
| HTTP listener on port 80 | Routes incoming HTTP requests to the target group containing ECS tasks. | Low | ALB, target group | Default action: `forward` to target group. Protocol `HTTP`, port `80`. |
| ALB security group | Controls what traffic can reach the ALB. Must allow HTTP from internet. | Low | VPC (existing) | Ingress: TCP port 80 from `0.0.0.0/0`. Egress: all traffic to `0.0.0.0/0` (needed for health checks to ECS tasks). |

### Target Group

| Feature | Why Expected | Complexity | Dependencies | Notes |
|---------|-------------|------------|--------------|-------|
| Target group (IP type) | Fargate with `awsvpc` mode registers task ENI IPs directly — **must** use `target_type = "ip"`. Using `"instance"` will silently fail. | Medium | VPC (existing) | `port = 5678`, `protocol = "HTTP"`, `vpc_id = aws_vpc.main.id`. Critical: Fargate always requires `target_type = "ip"`. |
| Health check configuration | ALB uses health checks to determine if tasks are healthy and should receive traffic. Misconfigured health checks = tasks constantly recycled. | Medium | None | `path = "/"` (http-echo responds 200 with configured text on **any** path). `matcher = "200"`. `interval = 30`, `timeout = 5`, `healthy_threshold = 2`, `unhealthy_threshold = 3`. Port: `"traffic-port"` (uses the target group port, 5678). |

### Security Groups

| Feature | Why Expected | Complexity | Dependencies | Notes |
|---------|-------------|------------|--------------|-------|
| ALB Security Group | Allows HTTP from internet, allows health check traffic to ECS. | Low | VPC (existing) | Ingress: port 80 from `0.0.0.0/0`. Egress: all traffic (required for ALB to reach ECS tasks on port 5678). |
| ECS Security Group | Restricts ECS task access to traffic from ALB only. Core security requirement. | Low | VPC, ALB SG | Ingress: port 5678 from ALB security group **only** (`source_security_group_id`). Egress: all traffic to `0.0.0.0/0` (needed for image pulls via NAT, DNS resolution, CloudWatch). |

### CloudWatch Logs

| Feature | Why Expected | Complexity | Dependencies | Notes |
|---------|-------------|------------|--------------|-------|
| CloudWatch Log Group | Must be created **before** ECS tasks start or the awslogs driver fails. README references `/aws/ecs/dna-interview-ecs` as the expected path. | Low | None | Name: `/aws/ecs/${module.this.id}`. Set `retention_in_days = 30` (or 14) — never leave as default (never-expire). Tags via `module.this.tags`. |

### Outputs

| Feature | Why Expected | Complexity | Dependencies | Notes |
|---------|-------------|------------|--------------|-------|
| `alb_dns_name` output | README explicitly requires this output. Needed to test the deployment with `curl http://<alb-dns-name>`. | Low | ALB | `value = aws_lb.main.dns_name` |
| `ecs_cluster_name` output | README explicitly requires this output. Useful for operational commands. | Low | ECS Cluster | `value = aws_ecs_cluster.main.name` |

---

## Differentiators

Features that demonstrate **best practices** and engineering maturity beyond the minimum. Not required for functionality but valued in interview evaluation.

| Feature | Value Proposition | Complexity | Dependencies | Notes |
|---------|------------------|------------|--------------|-------|
| `create_before_destroy` on target group | Prevents downtime during target group configuration changes (e.g., health check tuning). ALB keeps routing to old TG while new one is created. | Low | Target group | `lifecycle { create_before_destroy = true }`. Requires `name_prefix` instead of `name` (or use random suffix) to avoid name collisions. |
| ECS managed tags + tag propagation | Auto-tags running tasks with service/cluster metadata for cost tracking. Shows understanding of ECS tag lifecycle. | Low | ECS Service | `enable_ecs_managed_tags = true`, `propagate_tags = "SERVICE"` on the ECS service resource. |
| `depends_on` for NAT → IGW | Explicit ordering ensures NAT Gateway creation waits for IGW. Without it, creation can race and fail. AWS docs recommend this. | Low | NAT Gateway, IGW | `depends_on = [aws_internet_gateway.main]` on the NAT Gateway resource. |
| Descriptive security group rules | Using `description` on every SG rule makes the security posture auditable. Shows security-conscious thinking. | Low | Security groups | e.g., `description = "Allow HTTP from internet"`, `description = "Allow container port from ALB"` |
| `enable_deletion_protection = false` | Explicitly acknowledging this is a non-production resource. In production, this would be `true`. Shows awareness. | Low | ALB | Default is `false`, but being explicit in code with a comment shows intentionality. |
| Rolling deployment configuration | Setting `deployment_minimum_healthy_percent = 100` and `deployment_maximum_percent = 200` ensures zero-downtime deploys. | Low | ECS Service | Note: There's a known Terraform provider issue (#25503) where these values may be ignored if `deployment_circuit_breaker` block is present during initial creation. Test on subsequent applies. |
| `wait_for_steady_state = false` | Explicitly not waiting for service stabilization during `terraform apply`. Speeds up applies since Fargate tasks take 1-3 min to reach steady state. Note the alternative: `true` makes apply block until healthy (useful in CI/CD). | Low | ECS Service | Default is `false`. Being explicit shows awareness of the option. |

---

## Anti-Features

Features to explicitly **NOT** build in this milestone. Including them would add complexity, cost, or scope without value.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Multiple NAT Gateways (per-AZ) | ~$100/month total for 3 NAT Gateways. Single point of failure is acceptable for an interview exercise. If one AZ fails, the exercise won't be impacted. | Single NAT Gateway in `public[0]` subnet. Add a code comment noting this is a cost trade-off. |
| HTTPS/TLS on ALB | This is explicitly Exercise 3 scope. Adding it now couples milestones and blocks progress. | HTTP-only listener on port 80. ALB SG only needs port 80 ingress. |
| Auto-scaling (Application Auto Scaling) | Over-engineering for `desired_count = 1`. Auto-scaling needs target tracking policies, scaling thresholds, cooldowns — significant complexity for zero interview value in Exercise 1. | Static `desired_count = 1`. The deployment circuit breaker handles failure replacement. |
| Service discovery (Cloud Map) | No service-to-service communication in Exercise 1. Service discovery is for microservice architectures with internal routing. | Direct ALB → target group → ECS service routing. |
| Container health check in task definition | http-echo is a simple HTTP server with no `/health` endpoint distinction. The ALB target group health check on `"/"` is sufficient. Adding a container-level health check creates two competing health check systems. | Rely on ALB target group health check only. The task will be marked unhealthy if the target group health check fails, and ECS will replace it. |
| ECS Exec (execute command) | Useful for debugging but requires additional IAM permissions, VPC endpoints for SSM, and changes to the task role. The candidate IAM policy may not support the required SSM actions. | Debug via CloudWatch logs. Adequate for an http-echo container. |
| Capacity provider strategy | Adds unnecessary abstraction over `launch_type = "FARGATE"`. Capacity providers are valuable for Fargate Spot or mixed EC2/Fargate, neither of which applies here. | Use `launch_type = "FARGATE"` directly on the service. |
| Access logging for ALB | Requires an S3 bucket with a specific bucket policy for ELB access logging. Adds another resource + policy for minimal debugging value in an interview. | Rely on CloudWatch Container Insights for ALB metrics. |
| WAF / Shield integration | Production concern, not relevant for interview exercise. | Omit entirely. |
| VPC Endpoints (ECR, S3, CloudWatch) | Would eliminate NAT Gateway need for AWS service calls, but adds 3+ interface endpoints (~$7/mo each) and complexity. NAT Gateway handles all egress simply. | Route all outbound through NAT Gateway. |
| Blue/green deployment (CodeDeploy) | Requires `deployment_controller { type = "CODE_DEPLOY" }`, a CodeDeploy app, deployment group, two target groups, and a test listener. Massive complexity for zero value at this stage. | Use default ECS rolling deployment with circuit breaker. |

---

## Feature Dependencies

```
Elastic IP ─────────┐
                     ▼
Internet Gateway ──► NAT Gateway ──► Private Route Table ──► ECS Service (tasks can pull images)
(existing)           │
                     │
VPC (existing) ──────┤
                     │
                     ├──► ALB Security Group ──► ALB ──► HTTP Listener ──┐
                     │                                                    │
                     ├──► ECS Security Group ──► ECS Service ◄────────────┘
                     │         ▲                     │                   via Target Group
                     │         │                     │
                     │     (ingress from             ▼
                     │      ALB SG only)      Task Definition
                     │                          │         │
                     │                          ▼         ▼
                     │                   CloudWatch    IAM Roles
                     │                   Log Group    (existing)
                     │
                     └──► Target Group (IP type, health check on "/")
                              │
                              ▼
                     ECS Service registers task IPs here
```

### Critical ordering (must create before dependents):

1. **Elastic IP** → before NAT Gateway
2. **NAT Gateway** → before Private Route Table (needs `nat_gateway_id`)
3. **Private Route Table + Associations** → before ECS Service (tasks need egress)
4. **CloudWatch Log Group** → before ECS Task Definition (awslogs driver references it)
5. **Security Groups (both)** → before ALB and ECS Service
6. **ALB + Target Group + Listener** → before ECS Service (service references `target_group_arn`)
7. **ECS Cluster** → before ECS Service
8. **Task Definition** → before ECS Service

Terraform handles most ordering via resource references, but the NAT → IGW dependency should be explicit with `depends_on`.

---

## MVP Recommendation

### Must-have (in implementation order):

1. **NAT Gateway + Elastic IP + Private Route Table** — Without this, nothing else works. Tasks can't pull images.
2. **CloudWatch Log Group** — Create before task definition references it.
3. **Security Groups (ALB + ECS)** — Create before ALB and service. ALB SG must exist first since ECS SG references it.
4. **Target Group with health checks** — Create before ALB listener and ECS service.
5. **ALB + HTTP Listener** — Create before ECS service.
6. **ECS Cluster** — Simple, create anytime before service.
7. **ECS Task Definition** — Depends on log group and IAM roles.
8. **ECS Service** — The final resource that ties everything together.
9. **Outputs** — `alb_dns_name` and `ecs_cluster_name`.

### Defer to Exercise 2:
- RDS, DB subnet group, RDS security group, pgweb task definition changes

### Defer to Exercise 3:
- HTTPS listener, ACM certificate, Route53, HTTP→HTTPS redirect

---

## Terraform File Organization

Following the existing scaffold pattern of domain-based `.tf` file splitting:

| New File | Resources | Rationale |
|----------|-----------|-----------|
| `nat.tf` | `aws_eip.nat`, `aws_nat_gateway.main`, `aws_route_table.private`, `aws_route_table_association.private[*]` | Networking extension — separate from `vpc.tf` to keep scaffold untouched |
| `ecs.tf` | `aws_ecs_cluster.main`, `aws_ecs_task_definition.main`, `aws_ecs_service.main`, `aws_cloudwatch_log_group.ecs` | ECS domain resources |
| `alb.tf` | `aws_lb.main`, `aws_lb_target_group.main`, `aws_lb_listener.http` | Load balancer domain resources |
| `security-groups.tf` | `aws_security_group.alb`, `aws_security_group.ecs`, plus all ingress/egress rules | Security domain — centralized for auditability |

Extend existing `outputs.tf` with `alb_dns_name` and `ecs_cluster_name`.

---

## Sources

- AWS ECS Developer Guide: Container health checks — https://docs.aws.amazon.com/AmazonECS/latest/developerguide/healthcheck.html (HIGH confidence)
- Terraform AWS provider: `aws_ecs_service` resource docs — https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_service (HIGH confidence)
- Terraform AWS provider: `aws_ecs_cluster` resource docs — https://registry.terraform.io/providers/hashicorp/aws/3.44.0/docs/resources/ecs_cluster (HIGH confidence)
- hashicorp/http-echo GitHub — https://github.com/hashicorp/http-echo (HIGH confidence — confirmed port 5678 default, responds on any path)
- AWS re:Post: ECS Fargate health check failures — https://repost.aws/knowledge-center/ecs-fargate-health-check-failures (HIGH confidence)
- Terraform provider issue #25503: circuit breaker ignoring min/max healthy percent — https://github.com/hashicorp/terraform-provider-aws/issues/25503 (HIGH confidence — confirmed known bug)
- Terraform provider issue #19519: circuit breaker rollback with wait_for_steady_state — https://github.com/hashicorp/terraform-provider-aws/issues/19519 (HIGH confidence)
- ECS Fargate + ALB Terraform patterns — multiple blog sources cross-referenced (MEDIUM confidence)
- README.md, STEERING.md from project scaffold (HIGH confidence — primary requirements source)
