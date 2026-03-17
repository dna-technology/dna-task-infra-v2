# Roadmap: DNA Interview Infrastructure — ECS + ALB

## Overview

Deploy a containerized application on ECS Fargate behind an Application Load Balancer, building on the existing VPC scaffold. The work progresses from networking foundation (NAT Gateway for private subnet egress), through security group definitions, to ALB infrastructure, and finally the ECS service itself. All resources are applied together via `terraform apply` — phases represent logical review/verification boundaries, not separate deployments.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

- [ ] **Phase 1: Private Networking** - NAT Gateway and private subnet routing for ECS egress
- [ ] **Phase 2: Security Groups** - ALB and ECS security group definitions with least-privilege rules
- [ ] **Phase 3: Load Balancing** - ALB, target group, and HTTP listener in public subnets
- [ ] **Phase 4: ECS Service** - Cluster, task definition, service, logging, and outputs

## Phase Details

### Phase 1: Private Networking
**Goal**: Private subnets can route outbound traffic to the internet, enabling ECS tasks to pull container images and send logs
**Depends on**: Nothing (first phase; builds on existing VPC scaffold)
**Requirements**: NET-01, NET-02, NET-03
**Success Criteria** (what must be TRUE):
  1. `terraform plan` shows NAT Gateway resource with an Elastic IP in a public subnet
  2. `terraform plan` shows a route table with a `0.0.0.0/0` route pointing to the NAT Gateway
  3. All 3 private subnets are associated with the NAT Gateway route table (verified via `terraform plan` or `terraform state show`)
**Plans**: TBD

Plans:
- [ ] 01-01: TBD

### Phase 2: Security Groups
**Goal**: Network access controls exist that allow ALB to receive internet HTTP traffic and ECS tasks to accept traffic only from the ALB
**Depends on**: Phase 1
**Requirements**: SEC-01, SEC-02, SEC-03
**Success Criteria** (what must be TRUE):
  1. ALB security group allows inbound TCP port 80 from `0.0.0.0/0` and no other inbound rules
  2. ECS security group allows inbound TCP port 5678 from the ALB security group only (no CIDR-based rules)
  3. ECS security group allows outbound traffic (for image pulls, DNS resolution, and CloudWatch log delivery)
**Plans**: TBD

Plans:
- [ ] 02-01: TBD

### Phase 3: Load Balancing
**Goal**: An internet-facing Application Load Balancer accepts HTTP requests and can forward them to a target group with health checks configured
**Depends on**: Phase 2
**Requirements**: ALB-01, ALB-02, ALB-03
**Success Criteria** (what must be TRUE):
  1. `terraform apply` creates an ALB in public subnets that is reachable from the internet (DNS name resolves)
  2. HTTP listener on port 80 exists and forwards to a target group
  3. Target group uses IP target type with health check on path "/" expecting HTTP 200
**Plans**: TBD

Plans:
- [ ] 03-01: TBD

### Phase 4: ECS Service
**Goal**: A running ECS Fargate service serves HTTP traffic through the ALB — `curl http://<alb-dns-name>` returns the expected response with healthy targets
**Depends on**: Phase 3
**Requirements**: ECS-01, ECS-02, ECS-03, ECS-04, ECS-05, OBS-01, OUT-01, OUT-02
**Success Criteria** (what must be TRUE):
  1. ECS cluster exists with Fargate capacity provider and Container Insights enabled
  2. Task definition runs `hashicorp/http-echo:latest` on port 5678 with container logs sent to CloudWatch (log group exists with retention policy)
  3. ECS service runs in private subnets with deployment circuit breaker, rollback enabled, and health check grace period configured
  4. `curl http://<alb_dns_name>` returns a 200 response with the expected message — ALB target group shows healthy targets
  5. `terraform output alb_dns_name` and `terraform output ecs_cluster_name` return the correct values
**Plans**: TBD

Plans:
- [ ] 04-01: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Private Networking | 0/? | Not started | - |
| 2. Security Groups | 0/? | Not started | - |
| 3. Load Balancing | 0/? | Not started | - |
| 4. ECS Service | 0/? | Not started | - |
