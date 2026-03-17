# Requirements: DNA Interview Infrastructure — ECS + ALB

**Defined:** 2026-03-17
**Core Value:** A working ECS Fargate service serving HTTP traffic through an ALB — `curl http://<alb-dns-name>` returns "Hello from ECS!" with healthy targets.

## v1 Requirements

Requirements for milestone v1.0. Each maps to roadmap phases.

### Networking

- [ ] **NET-01**: Private subnets can route outbound traffic to the internet via NAT Gateway
- [ ] **NET-02**: NAT Gateway has a dedicated Elastic IP in a public subnet
- [ ] **NET-03**: All 3 private subnets are associated with a route table that routes through the NAT Gateway

### ECS Compute

- [ ] **ECS-01**: ECS Cluster exists with Fargate capacity and Container Insights enabled
- [ ] **ECS-02**: Task definition runs `hashicorp/http-echo:latest` on port 5678 with 256 CPU / 512 MiB memory
- [ ] **ECS-03**: Task definition sends container logs to CloudWatch via awslogs driver
- [ ] **ECS-04**: ECS Service runs in private subnets with deployment circuit breaker and rollback enabled
- [ ] **ECS-05**: ECS Service has health check grace period to prevent premature task termination

### Load Balancing

- [ ] **ALB-01**: Application Load Balancer is deployed in public subnets and accessible from the internet
- [ ] **ALB-02**: HTTP listener on port 80 forwards traffic to the target group
- [ ] **ALB-03**: Target group uses IP target type with health checks on path "/" returning 200

### Security

- [ ] **SEC-01**: ALB security group allows inbound HTTP (port 80) from 0.0.0.0/0
- [ ] **SEC-02**: ECS security group allows inbound traffic on container port (5678) from ALB security group only
- [ ] **SEC-03**: ECS security group allows outbound traffic for image pulls, DNS, and CloudWatch

### Observability

- [ ] **OBS-01**: CloudWatch Log Group exists for ECS container logs with a retention policy

### Outputs

- [ ] **OUT-01**: `alb_dns_name` output exposes the ALB DNS name for testing
- [ ] **OUT-02**: `ecs_cluster_name` output exposes the ECS cluster name

## v2 Requirements

Deferred to future milestones. Tracked but not in current roadmap.

### Exercise 2 — RDS + pgweb

- **RDS-01**: RDS PostgreSQL 16.6 instance in private subnets
- **RDS-02**: DB subnet group across all AZs
- **RDS-03**: RDS security group allowing port 5432 from ECS SG only
- **RDS-04**: Updated ECS task running `sosedoff/pgweb:latest` with connection string

### Exercise 3 — Route53 + HTTPS

- **DNS-01**: Route53 hosted zone with A record alias to ALB
- **DNS-02**: ACM certificate with DNS validation
- **DNS-03**: HTTPS listener on ALB port 443 with TLS 1.3 policy
- **DNS-04**: HTTP-to-HTTPS redirect

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Multiple NAT Gateways (per-AZ) | Cost optimization — single NAT sufficient for interview exercise |
| Auto-scaling (Application Auto Scaling) | Over-engineering for desired_count=1 |
| Service Discovery (Cloud Map) | No service-to-service communication in Exercise 1 |
| HTTPS/TLS on ALB | Exercise 3 scope — separate milestone |
| ECS Exec (execute command) | Requires additional IAM/VPC endpoints; debug via CloudWatch logs |
| Blue/green deployment (CodeDeploy) | Massive complexity for zero value at this stage |
| VPC Endpoints (ECR, S3, CloudWatch) | NAT Gateway handles all egress simply |
| Container health check in task def | ALB target group health check on "/" is sufficient |
| WAF / Shield integration | Production concern, not relevant for interview |
| ALB access logging | Requires S3 bucket + policy for minimal value |
| VPC Flow Logs | Not required for interview exercise |
| Automated testing (terratest/checkov) | Useful but not in scope for this milestone |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| NET-01 | Phase 1: Private Networking | Pending |
| NET-02 | Phase 1: Private Networking | Pending |
| NET-03 | Phase 1: Private Networking | Pending |
| SEC-01 | Phase 2: Security Groups | Pending |
| SEC-02 | Phase 2: Security Groups | Pending |
| SEC-03 | Phase 2: Security Groups | Pending |
| ALB-01 | Phase 3: Load Balancing | Pending |
| ALB-02 | Phase 3: Load Balancing | Pending |
| ALB-03 | Phase 3: Load Balancing | Pending |
| ECS-01 | Phase 4: ECS Service | Pending |
| ECS-02 | Phase 4: ECS Service | Pending |
| ECS-03 | Phase 4: ECS Service | Pending |
| ECS-04 | Phase 4: ECS Service | Pending |
| ECS-05 | Phase 4: ECS Service | Pending |
| OBS-01 | Phase 4: ECS Service | Pending |
| OUT-01 | Phase 4: ECS Service | Pending |
| OUT-02 | Phase 4: ECS Service | Pending |

**Coverage:**
- v1 requirements: 17 total
- Mapped to phases: 17
- Unmapped: 0 ✓

---
*Requirements defined: 2026-03-17*
*Last updated: 2026-03-17 after roadmap creation*
