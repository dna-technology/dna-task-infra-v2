# DNA Interview Infrastructure — ECS + ALB

## What This Is

A Terraform/OpenTofu infrastructure project that provisions AWS resources for a containerized application deployment. The scaffold provides base networking (VPC, subnets, IGW) and ECS IAM roles; the goal is to complete Exercise 1 by deploying an ECS Fargate service behind an Application Load Balancer, accessible over HTTP.

## Core Value

A working ECS Fargate service serving HTTP traffic through an ALB — `curl http://<alb-dns-name>` returns "Hello from ECS!" with healthy targets.

## Current Milestone: v1.0 ECS + ALB

**Goal:** Deploy a containerized application on ECS Fargate accessible via Application Load Balancer.

**Target features:**
- NAT Gateway for private subnet egress (missing from scaffold)
- ECS Cluster with Fargate and Container Insights
- ECS Task Definition running `hashicorp/http-echo:latest`
- ECS Service in private subnets with deployment circuit breaker
- Application Load Balancer in public subnets with HTTP listener
- Security groups (ALB: HTTP from internet; ECS: traffic from ALB only)
- Target group with health checks (IP target type for Fargate)
- CloudWatch log group for ECS container logs

## Requirements

### Validated

<!-- Shipped and confirmed valuable. -->

- VPC with public/private subnets across 3 AZs (`vpc.tf`)
- Internet gateway + public route table (`vpc.tf`)
- ECS task execution IAM role with managed policy (`iam-ecs.tf`)
- ECS task IAM role (`iam-ecs.tf`)
- CloudPosse null-label naming/tagging (`context.tf`)
- S3/DynamoDB remote state backend (`main.tf`)

### Active

<!-- Current scope. Building toward these. -->

- [ ] NAT Gateway + private subnet route table
- [ ] ECS Cluster (Fargate, Container Insights)
- [ ] ECS Task Definition (http-echo, port 5678, CloudWatch logs)
- [ ] ECS Service (private subnets, circuit breaker)
- [ ] ALB (public subnets, HTTP listener port 80)
- [ ] ALB Security Group (HTTP from 0.0.0.0/0)
- [ ] ECS Security Group (container port from ALB SG only)
- [ ] Target Group (IP type, health checks)
- [ ] CloudWatch Log Group
- [ ] Terraform outputs (alb_dns_name, ecs_cluster_name)

### Out of Scope

<!-- Explicit boundaries. Includes reasoning to prevent re-adding. -->

- Exercise 2 (RDS + pgweb) — Separate milestone, builds on Exercise 1
- Exercise 3 (Route53 + HTTPS) — Separate milestone, builds on Exercise 2
- Multiple NAT Gateways per AZ — Cost optimization, single NAT is sufficient for interview
- VPC Flow Logs — Not required for interview exercise
- Automated testing (terratest/checkov) — Useful but not in scope for this milestone

## Context

- **Codebase:** Terraform interview exercise scaffold from LoomIS/DNA
- **Existing infra:** VPC (`10.64.0.0/20`), 3 public + 3 private subnets, IGW, ECS IAM roles
- **Known issue:** README claims NAT Gateway is pre-created but it is not — must be added
- **Naming:** All resources use `module.this.id` prefix → `dna-interview-ecs`
- **Region:** `eu-west-1` (Ireland), 3 AZs
- **Container:** `hashicorp/http-echo:latest` on port 5678, responds with configurable text
- **STEERING.md:** Establishes IaC principles (DRY, KISS, Security First, Immutability, consistent naming via context.tf)

## Constraints

- **Tech stack**: Terraform/OpenTofu >= 1.0, AWS provider ~> 5.0 — Interview requirement
- **Region**: `eu-west-1` only — IAM policy restricts to this region
- **Naming**: Must use `module.this.id` and `module.this.tags` — CloudPosse convention enforced by STEERING.md
- **IAM**: Cannot create IAM users/roles — Candidate policy denies this (except pre-existing ECS roles)
- **Budget**: Minimal resources — db.t4g.micro, single NAT Gateway, smallest Fargate config

## Key Decisions

<!-- Decisions that constrain future work. Add throughout project lifecycle. -->

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Single NAT Gateway (not per-AZ) | Cost optimization for interview exercise | — Pending |
| Private subnets for ECS tasks | Security best practice per README requirements | — Pending |
| Domain-based .tf file splitting | Follows existing scaffold pattern (vpc.tf, iam-ecs.tf) | — Pending |

---
*Last updated: 2026-03-17 after milestone v1.0 initialization*
