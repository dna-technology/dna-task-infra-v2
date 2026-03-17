# External Integrations

**Analysis Date:** 2026-03-17

## APIs & External Services

**Terraform Registry:**
- HashiCorp Terraform Registry - Provider and module downloads
  - Providers: `hashicorp/aws` ~> 5.0, `hashicorp/null` ~> 3.0
  - Modules: `cloudposse/label/null` v0.25.0
  - Used during `tofu init` / `terraform init`

**AWS API (via Terraform AWS Provider):**
- All infrastructure provisioning happens via AWS API calls
  - Auth: `AWS_ACCESS_KEY_ID` + `AWS_SECRET_ACCESS_KEY` environment variables
  - Region: `eu-west-1` (configured in `main.tf` line 25 and `variables.tf` line 4)

## AWS Services Used (Current State)

**Networking (provisioned in `vpc.tf`):**
- **Amazon VPC** - Virtual Private Cloud (`aws_vpc.main`)
  - CIDR: `10.64.0.0/20`
- **EC2 Subnets** - 3 public + 3 private subnets across AZs (`aws_subnet.public`, `aws_subnet.private`)
- **Internet Gateway** - Public internet access (`aws_internet_gateway.main`)
- **Route Tables** - Public routing via IGW (`aws_route_table.public`)

**IAM (provisioned in `iam-ecs.tf`):**
- **IAM Role: ECS Task Execution** - `${module.this.id}-ecs-task-execution`
  - Assumes: `ecs-tasks.amazonaws.com`
  - Policy: `AmazonECSTaskExecutionRolePolicy` (managed)
- **IAM Role: ECS Task** - `${module.this.id}-ecs-task`
  - Assumes: `ecs-tasks.amazonaws.com`
  - No additional policies attached (application-level permissions)

## AWS Services Expected (Interview Exercises)

**Exercise 1 - ECS + ALB:**
- **Amazon ECS (Fargate)** - Container orchestration
  - Container image: `hashicorp/http-echo:latest` (Docker Hub)
  - Container port: 5678
  - CPU: 256, Memory: 512 MB
- **Application Load Balancer (ALB)** - HTTP load balancing on port 80
- **CloudWatch Logs** - ECS container log group `/aws/ecs/dna-interview-ecs`
- **EC2 Security Groups** - ALB ingress (HTTP/80) + ECS ingress (from ALB on container port)
- **ELB Target Groups** - IP-type targets for Fargate

**Exercise 2 - RDS:**
- **Amazon RDS (PostgreSQL 16.6)** - Managed database
  - Instance class: `db.t4g.micro`
  - Storage: 20 GB gp3 with auto-scaling
  - Encryption enabled
  - Deployed in private subnets
- **Container image change:** `sosedoff/pgweb:latest` (Docker Hub) - PostgreSQL web client
  - Container port: 8080
  - Connects to RDS via PostgreSQL connection string

**Exercise 3 - DNS + HTTPS:**
- **Route53** - DNS hosted zone and A record (alias to ALB)
- **ACM (AWS Certificate Manager)** - SSL/TLS certificate with DNS validation
- **ALB HTTPS Listener** - Port 443 with ACM certificate
  - SSL Policy: `ELBSecurityPolicy-TLS13-1-2-2021-06` (recommended)

## Data Storage

**Terraform State:**
- **S3** - Remote state storage
  - Bucket: `dna-stag-terraform-state`
  - Key: `interview/terraform.tfstate`
  - Encryption: enabled
  - Config: `main.tf` lines 15-21

- **DynamoDB** - State locking
  - Table: `dna-stag-terraform-locks`
  - Partition key: `LockID` (String)
  - Billing: PAY_PER_REQUEST
  - Setup script: `setup/setup-dynamodb-lock.sh`

**Application Databases (Exercise 2):**
- PostgreSQL 16.6 via Amazon RDS (to be provisioned by candidate)

**File Storage:**
- None - No S3 buckets for application data

**Caching:**
- None

## Authentication & Identity

**AWS Auth:**
- Environment variable-based credentials
  - `AWS_ACCESS_KEY_ID`
  - `AWS_SECRET_ACCESS_KEY`
  - `AWS_DEFAULT_REGION`
- IAM policy for interview candidates: `setup/interview-candidate-policy.json`
  - Scoped to `eu-west-1` region
  - Denies dangerous actions (IAM user/role creation, EC2 instances, bucket deletion)
  - Allows: VPC, EC2 networking, Security Groups, ECS, RDS, ALB, Route53, ACM, CloudWatch Logs

**Application Auth:**
- Not applicable - Infrastructure-only codebase

## Monitoring & Observability

**Error Tracking:**
- None configured at infrastructure level

**Logs:**
- CloudWatch Logs expected for ECS containers (log group pattern: `/aws/ecs/dna-interview-ecs`)
- No logging infrastructure provisioned in base code (candidates add it in Exercise 1)

## CI/CD & Deployment

**Hosting:**
- AWS (account `105458107979`, region `eu-west-1`)

**CI Pipeline:**
- None - Manual `tofu plan` / `tofu apply` workflow
- No GitHub Actions, Jenkins, or other CI configuration detected

**Deployment Process:**
1. `tofu init` - Initialize providers and backend
2. `tofu plan` - Preview changes
3. `tofu apply` - Apply infrastructure changes

## Environment Configuration

**Required env vars:**
- `AWS_ACCESS_KEY_ID` - AWS IAM access key
- `AWS_SECRET_ACCESS_KEY` - AWS IAM secret key
- `AWS_DEFAULT_REGION` - Should be `eu-west-1`

**Secrets location:**
- AWS credentials in shell environment (not stored in repo)
- Credential files gitignored: `setup/credentials-*.txt` (`.gitignore` line 14)
- `terraform.tfvars` is gitignored (`.gitignore` line 5) but present in repo for interview context

## Webhooks & Callbacks

**Incoming:**
- None

**Outgoing:**
- None

## Container Images (External Dependencies)

**Docker Hub images referenced in README exercises:**
- `hashicorp/http-echo:latest` - Simple HTTP echo server (Exercise 1)
- `sosedoff/pgweb:latest` - PostgreSQL web client (Exercise 2)

These are pulled by ECS Fargate at runtime and require outbound internet access (via NAT Gateway in private subnets).

---

*Integration audit: 2026-03-17*
