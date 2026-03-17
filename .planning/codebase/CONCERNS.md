# Codebase Concerns

**Analysis Date:** 2026-03-17

## Tech Debt

**Missing NAT Gateway for Private Subnets:**
- Issue: The `README.md` states "NAT Gateway for private subnet internet access" is a pre-created resource, but no NAT Gateway, Elastic IP, or private route table resources exist in `vpc.tf`. Private subnets have no internet-routable path, which means ECS Fargate tasks deployed in private subnets (as Exercise 1 requires) cannot pull container images from public registries (Docker Hub, ECR public) or reach any external service.
- Files: `vpc.tf`
- Impact: **Critical blocker for Exercise 1/2/3.** ECS tasks in private subnets will fail to start because Fargate needs to pull images. The README promises this exists but it does not.
- Fix approach: Add `aws_eip`, `aws_nat_gateway` (in a public subnet), `aws_route_table` for private subnets with a default route via the NAT Gateway, and `aws_route_table_association` for each private subnet. Alternatively, add VPC endpoints for ECR/S3/CloudWatch if avoiding NAT Gateway costs.

**Missing ECS Cluster, ALB, Security Groups, and All Exercise Resources:**
- Issue: The README describes 3 progressive exercises the candidate must build, but the base infrastructure is incomplete. Only VPC networking (partially - see NAT Gateway concern) and IAM roles are pre-provisioned. The codebase is intentionally a starting scaffold for an interview exercise.
- Files: `main.tf`, `vpc.tf`, `iam-ecs.tf`, `outputs.tf`
- Impact: This is by design (interview task), but the gap between what `README.md` claims is "pre-created" and what actually exists causes confusion. The README says NAT Gateway is pre-created, but it is not.
- Fix approach: Either add the NAT Gateway to the base scaffold, or update `README.md` to accurately list only what is pre-created (VPC, subnets, IGW, public route table, IAM roles).

**No CloudWatch Log Group Pre-created:**
- Issue: Exercise 1 requires "CloudWatch logs integration" for ECS tasks, but no `aws_cloudwatch_log_group` resource exists in the base infrastructure. The candidate must create it.
- Files: No existing file defines this resource.
- Impact: Minor - candidate is expected to add this. But if this was intended to be pre-created, it's missing.
- Fix approach: Add `aws_cloudwatch_log_group` resource to the base scaffold if desired, or document that it must be created by the candidate.

**IAM Policy ARN Has Missing Account ID:**
- Issue: The `aws_iam_role_policy_attachment.ecs_task_execution` resource references `arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy` with a double colon (`::`) between `iam` and `aws`. AWS managed policy ARNs use this format correctly (the account field is empty for AWS-managed policies), but confusingly the `setup/interview-candidate-policy.json` references `arn:aws:iam::105458107979:role/dna-interview-ecs-*` which also has a double colon — this is a malformed ARN that should be `arn:aws:iam:105458107979:role/dna-interview-ecs-*` (IAM ARNs have no region, so the format is `arn:aws:iam::ACCOUNT:resource`). Actually this is correct IAM ARN format. The double colon is intentional since IAM is global (no region field). No issue here.
- Files: `iam-ecs.tf` (line 29)
- Impact: None — the ARN format is correct for AWS-managed IAM policies.
- Fix approach: No fix needed.

**ECS Task Role Has No Policies Attached:**
- Issue: `aws_iam_role.ecs_task` (the application-level task role) is created but has zero policies attached. Any ECS task using this role will have no AWS permissions at all.
- Files: `iam-ecs.tf` (lines 32-55)
- Impact: Low for Exercises 1-2 (http-echo and pgweb don't need AWS API access). However, if any future exercise requires the container to call AWS services (e.g., S3, SQS, Secrets Manager), the task role needs policies.
- Fix approach: This is likely intentional for the scaffold. If tasks need AWS permissions, attach specific policies. Consider adding Secrets Manager access policy if RDS credentials are stored there (Exercise 2 security best practice).

## Known Bugs

**README Claims NAT Gateway Exists But It Does Not:**
- Symptoms: README line 9 states "NAT Gateway for private subnet internet access" is a pre-created resource. This is false — no NAT Gateway resource exists in any `.tf` file.
- Files: `README.md` (line 9), `vpc.tf`
- Trigger: Candidate reads README, assumes NAT Gateway exists, deploys ECS tasks in private subnets, tasks fail to pull images.
- Workaround: Candidate must create the NAT Gateway themselves, or deploy ECS tasks in public subnets with `assign_public_ip = true` (less secure but functional).

**`.gitignore` Excludes `*.tfvars` But `terraform.tfvars` Is Committed:**
- Symptoms: The `.gitignore` has `*.tfvars` which should exclude `terraform.tfvars`, but the file is tracked in git (likely was added before the gitignore rule, or was force-added).
- Files: `.gitignore` (line 6), `terraform.tfvars`
- Trigger: New `.tfvars` files won't be tracked, but the existing one is. Running `git status` may show confusing behavior.
- Workaround: This is a minor inconsistency. The `terraform.tfvars` contains no secrets (only naming conventions and CIDR), so it's fine to keep it tracked. Consider removing `*.tfvars` from `.gitignore` or using a more specific pattern like `*.auto.tfvars` or `secret.tfvars`.

## Security Considerations

**No VPC Flow Logs:**
- Risk: No `aws_flow_log` resource exists. Network traffic within the VPC is not logged, making it difficult to audit or debug network connectivity issues.
- Files: `vpc.tf`
- Current mitigation: None.
- Recommendations: Add VPC flow logs to CloudWatch or S3 for production environments. Acceptable to skip for an interview exercise.

**Public Subnets Auto-Assign Public IPs:**
- Risk: `map_public_ip_on_launch = true` in `vpc.tf` (line 33) means any resource launched in public subnets gets a public IP automatically. If a candidate accidentally deploys a database or internal service in a public subnet, it will be publicly accessible.
- Files: `vpc.tf` (line 33)
- Current mitigation: Exercise instructions specify deploying ECS and RDS in private subnets.
- Recommendations: This is standard for public subnets and required for ALB. The security groups will be the actual access control layer. Acceptable as-is.

**IAM Candidate Policy Allows Broad Resource Access:**
- Risk: The `setup/interview-candidate-policy.json` uses `"Resource": "*"` for most service actions (ECS, RDS, ALB, Security Groups, etc.), constrained only by region. Within eu-west-1, the candidate can create/delete any resource of those types, not just their own.
- Files: `setup/interview-candidate-policy.json`
- Current mitigation: `DenyDangerousActions` statement blocks the most destructive actions (creating IAM users/roles, launching EC2 instances, deleting S3 buckets). Region-locked to eu-west-1 via `DenyOtherRegions`.
- Recommendations: Acceptable for an interview exercise. For a shared interview environment, consider adding resource-level tagging conditions to prevent candidates from affecting each other's resources.

**No State File Encryption Key Specified:**
- Risk: The S3 backend in `main.tf` uses `encrypt = true` but does not specify a KMS key ARN via `kms_key_id`. This means AWS-managed S3 encryption (SSE-S3) is used, not customer-managed KMS.
- Files: `main.tf` (line 19)
- Current mitigation: SSE-S3 encryption is enabled (default AWS encryption).
- Recommendations: For production, use a customer-managed KMS key. Acceptable for an interview exercise.

**Terraform State Contains Secrets in Plaintext:**
- Risk: When Exercise 2 adds RDS with `username` and `password` attributes, these values will be stored in the Terraform state file in plaintext in the S3 bucket. Anyone with S3 read access to the state bucket can see database credentials.
- Files: `main.tf` (S3 backend config)
- Current mitigation: S3 encryption at rest. Candidate IAM policy restricts state access to `interview/*` prefix.
- Recommendations: Use `sensitive = true` on password variables. For production, use AWS Secrets Manager or SSM Parameter Store for credentials and reference them in Terraform rather than hardcoding.

## Performance Bottlenecks

**Single NAT Gateway (When Added):**
- Problem: When the missing NAT Gateway is added, if only one is created (common cost-saving approach), all private subnet traffic across 3 AZs will route through a single NAT Gateway in one AZ.
- Files: `vpc.tf`
- Cause: Cost optimization vs. high availability tradeoff.
- Improvement path: For production, create one NAT Gateway per AZ (3 total) for high availability and to avoid cross-AZ traffic charges. For interview purposes, a single NAT Gateway is fine.

## Fragile Areas

**VPC CIDR Subnet Calculation:**
- Files: `vpc.tf` (lines 31, 49)
- Why fragile: Public subnets use `cidrsubnet(var.vpc_cidr, 8, count.index)` (offsets 0, 1, 2) and private subnets use `cidrsubnet(var.vpc_cidr, 8, count.index + 10)` (offsets 10, 11, 12). The gap (offsets 3-9) is undocumented. If someone adds more subnets (e.g., database subnets at offset 3-5), the implicit allocation scheme is not obvious.
- Safe modification: Document the subnet allocation scheme with a comment or `locals` block mapping purpose to offset. When adding new subnets, use offsets in the documented gap (3-9 or 13+).
- Test coverage: No automated tests. Validate with `tofu plan` to ensure no CIDR overlaps.

**Context Module Version Pinning:**
- Files: `context.tf` (line 25)
- Why fragile: The `cloudposse/label/null` module is pinned to `0.25.0`. This file is a vendored copy from the CloudPosse repository. If the module is updated upstream, the local `context.tf` variable definitions may drift from the module's expectations.
- Safe modification: Do not manually edit `context.tf`. If upgrading the module version, re-download the entire file from the CloudPosse repository using the curl command in the file header.
- Test coverage: None. Run `tofu init -upgrade` and `tofu plan` to validate.

**Hardcoded S3 Backend Configuration:**
- Files: `main.tf` (lines 15-21)
- Why fragile: The S3 backend block uses hardcoded values (bucket name, DynamoDB table, region). Terraform backend blocks cannot use variables. If the state bucket or table name changes, every developer must update their local config.
- Safe modification: Use `-backend-config` partial configuration files or environment-specific backend configs. Document the backend values clearly (currently done in `README.md` line 265-267).
- Test coverage: None possible for backend config — it's validated during `tofu init`.

## Scaling Limits

**VPC CIDR Block Size:**
- Current capacity: `10.64.0.0/20` provides 4,096 IP addresses. With `/24` subnets (256 IPs each via `cidrsubnet(..., 8, ...)`), this supports up to 16 subnets.
- Limit: Currently 3 public + 3 private = 6 subnets used. 10 more `/24` subnets can fit. However, 256 IPs per subnet may be limiting for large ECS deployments (Fargate tasks each consume an ENI/IP).
- Scaling path: For the interview exercise, this is more than sufficient. For production, use a larger CIDR (e.g., `/16`) or plan subnet sizes more carefully.

## Dependencies at Risk

**CloudPosse terraform-null-label Module:**
- Risk: The `context.tf` file is a vendored copy tied to module version `0.25.0`. This is a widely-used, stable module, so risk is low. However, it adds 272 lines of boilerplate variable definitions to the project.
- Impact: If the module has a breaking change, `context.tf` must be updated in sync.
- Migration plan: No migration needed. Keep version pinned. Update only when needed by re-downloading from CloudPosse.

**hashicorp/null Provider:**
- Risk: The `null` provider (version `~> 3.0`) is declared in `main.tf` but never used by any resource. It's dead code.
- Impact: Adds unnecessary provider download during `tofu init`. No functional impact.
- Migration plan: Remove the `null` provider from `required_providers` unless it's expected to be used by candidate-added resources (e.g., `null_resource` for provisioners).

## Missing Critical Features

**No NAT Gateway (Private Subnet Egress):**
- Problem: Private subnets have no route to the internet. ECS Fargate tasks cannot pull container images or reach external services.
- Blocks: Exercise 1 (ECS deployment), Exercise 2 (RDS connectivity from ECS, image pull), Exercise 3 (all functionality depends on working ECS).

**No Private Subnet Route Table:**
- Problem: No `aws_route_table` or `aws_route_table_association` exists for private subnets. Even if a NAT Gateway were added, there's no route table to direct traffic through it.
- Blocks: Same as NAT Gateway — private subnets are effectively isolated with no outbound internet path.

**No ECS Cluster or Service Resources:**
- Problem: No ECS cluster, task definition, or service exists. These are required for all three exercises.
- Blocks: This is intentional — the candidate is expected to create them. Not a bug, but worth noting that the scaffold only provides VPC + IAM.

**No Outputs for Exercise Resources:**
- Problem: `outputs.tf` only exports VPC and subnet IDs. The README expects outputs like `alb_dns_name`, `ecs_cluster_name`, `rds_endpoint`, etc.
- Blocks: Candidate must add these outputs as they build each exercise.

## Test Coverage Gaps

**No Automated Tests:**
- What's not tested: The entire infrastructure codebase has zero automated tests. No `terratest`, `kitchen-terraform`, or policy-as-code tools (OPA, Sentinel, Checkov, tfsec) are configured.
- Files: All `.tf` files
- Risk: Infrastructure changes could introduce security misconfigurations (open security groups, unencrypted storage, overly permissive IAM) without detection. CIDR calculations could overlap without warning until `tofu plan`.
- Priority: Low for interview exercise. High for production use. The STEERING.md recommends "Run tfsec or checkov before deployment" but no tooling is configured.

**No Validation of Pre-existing Resources:**
- What's not tested: There is no validation that the S3 state bucket (`dna-stag-terraform-state`) and DynamoDB lock table (`dna-stag-terraform-locks`) actually exist before `tofu init`. The `setup/setup-dynamodb-lock.sh` script creates the DynamoDB table but there's no corresponding script for the S3 bucket.
- Files: `main.tf` (backend config), `setup/setup-dynamodb-lock.sh`
- Risk: If the S3 bucket doesn't exist, `tofu init` will fail with an unclear error. If the DynamoDB table doesn't exist, state locking will fail.
- Priority: Medium — affects initial setup experience for interview candidates.

---

*Concerns audit: 2026-03-17*
