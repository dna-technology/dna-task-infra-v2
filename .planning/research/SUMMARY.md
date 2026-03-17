# Research Summary: ECS Fargate + ALB Deployment

**Domain:** Terraform AWS infrastructure — ECS Fargate service behind ALB
**Researched:** 2026-03-17
**Overall confidence:** HIGH

## Executive Summary

The ECS Fargate + ALB deployment on the existing VPC scaffold requires exactly 17 new Terraform resources across 14 resource types. The architecture is well-established: ALB in public subnets receives HTTP traffic, forwards to an IP-type target group, which routes to ECS Fargate tasks running in private subnets. A single NAT Gateway provides egress for container image pulls and CloudWatch log delivery.

All required resource types are fully supported by the AWS provider ~> 5.0 and all required IAM actions are permitted by the interview candidate policy. The only constraint is that IAM roles cannot be created or modified (DenyDangerousActions), but the existing scaffold already provides the needed ECS execution and task roles.

The technology choices are straightforward with no ambiguity: Fargate requires `awsvpc` network mode, `target_type = "ip"` for target groups, and `awslogs-stream-prefix` in log configuration. The smallest Fargate configuration (256 CPU / 512 MiB memory) is more than sufficient for the http-echo container.

The main risk areas are: (1) missing the `depends_on` for NAT Gateway → Internet Gateway, causing creation failures; (2) container_name/container_port mismatches between task definition and ECS service load_balancer block; and (3) forgetting the `health_check_grace_period_seconds` on the ECS service, causing premature task termination.

## Key Findings

**Stack:** 17 new resources using standard AWS provider resource types — no modules, no external dependencies needed.
**Architecture:** Public ALB → Private ECS Fargate tasks via IP target group, single NAT Gateway for egress.
**Critical pitfall:** Container name mismatch between task definition and ECS service `load_balancer.container_name` causes silent failures where targets never become healthy.

## Implications for Roadmap

Based on research, the implementation should follow this order:

1. **NAT Gateway + private routing** - Must exist before ECS tasks can pull images
   - Addresses: Private subnet egress requirement
   - Avoids: ECS tasks failing to start due to no internet access

2. **Security groups** - Must exist before ALB and ECS service reference them
   - Addresses: ALB and ECS security group requirements
   - Avoids: Circular dependency issues if created alongside consumers

3. **ALB + Target Group + Listener** - Must exist before ECS service references them
   - Addresses: Load balancer infrastructure
   - Avoids: ECS service `depends_on` failures

4. **ECS Cluster + Log Group + Task Definition + Service** - Final step, references everything above
   - Addresses: Container orchestration
   - Avoids: Missing dependencies

**Phase ordering rationale:**
- Terraform handles most dependency ordering automatically via resource references
- The explicit `depends_on` requirements (NAT→IGW, Service→Listener) must be coded correctly
- All 17 resources can be in a single `terraform apply` — Terraform's dependency graph handles the order

**Research flags:**
- No deeper research needed — all patterns are well-established and verified
- Exercise 2 (RDS) and Exercise 3 (Route53/HTTPS) will need separate research phases

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All resource types verified against provider 5.x docs |
| Features | HIGH | Requirements are explicit in PROJECT.md |
| Architecture | HIGH | Standard ALB + Fargate pattern, well-documented |
| Pitfalls | HIGH | Based on common issues documented in community |
| IAM constraints | HIGH | Directly verified against candidate policy JSON |

## Gaps to Address

- Exercise 2 (RDS + pgweb) resource types — separate research needed
- Exercise 3 (Route53 + ACM + HTTPS listener) — separate research needed
- Whether `hashicorp/http-echo:latest` tag resolves correctly on Fargate (it should, but verify at deploy time)
- Whether the existing IAM roles in `iam-ecs.tf` can actually be applied given the DenyDangerousActions policy (they may need to have been pre-applied by an admin)

---

*Summary: 2026-03-17*
