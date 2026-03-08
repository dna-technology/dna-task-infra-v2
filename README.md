# AWS Infrastructure Interview Task

## Overview
This is a live coding interview exercise where candidates will create AWS infrastructure using Terraform/OpenTofu in three progressive stages.

## Pre-created Resources (Provided)
- VPC with public/private subnets across 3 availability zones
- NAT Gateway for private subnet internet access
- IAM roles for ECS tasks
- Base networking (Internet Gateway, Route Tables)
- S3 backend for state management
- DynamoDB table for state locking

## Interview Structure

The interview is divided into 3 progressive exercises. Each builds upon the previous one.

---

## Exercise 1: ECS Cluster + Application Load Balancer

**Goal:** Deploy a simple containerized application accessible via ALB

### Required Components
1. **ECS Cluster**
   - Fargate launch type
   - Container Insights enabled

2. **ECS Task Definition**
   - Use image: `hashicorp/http-echo:latest`
   - Container port: 5678
   - Configure appropriate CPU/memory (256 CPU, 512 MB recommended)
   - CloudWatch logs integration

3. **ECS Service**
   - Deploy in private subnets
   - Link to ALB target group
   - Configure deployment circuit breaker

4. **Application Load Balancer (ALB)**
   - Deploy in public subnets
   - HTTP listener on port 80
   - Security group allowing HTTP traffic from internet

5. **Security Groups**
   - ALB security group (allow HTTP from 0.0.0.0/0)
   - ECS security group (allow traffic from ALB on container port)

6. **Target Group**
   - Configure health checks
   - Target type: IP (for Fargate)

### Success Criteria
- Access ALB DNS name in browser
- See "Hello from ECS!" message
- ECS tasks running healthy
- Target group shows healthy targets

### Example Configuration
```bash
# Test the deployment
curl http://<alb-dns-name>
# Expected: Hello from ECS!
```

---

## Exercise 2: Add RDS Database + PostgreSQL Web Client

**Goal:** Add PostgreSQL RDS database and deploy a web-based database client to test connectivity

### Required Components
1. **RDS PostgreSQL Instance**
   - Engine: PostgreSQL 16.6
   - Instance class: db.t4g.micro (smallest available)
   - Deploy in private subnets
   - Storage: 20 GB gp3 with auto-scaling
   - Enable encryption
   - Configure backup retention

2. **DB Subnet Group**
   - Use private subnets from all AZs

3. **RDS Security Group**
   - Allow PostgreSQL (5432) from ECS security group only

4. **Update ECS Task Definition**
   - Change image to: `sosedoff/pgweb:latest` (PostgreSQL web client)
   - Update CPU/memory: 256 CPU, 512 MB
   - Configure command with PostgreSQL connection string:
     ```
     --bind=0.0.0.0
     --listen=8080
     --url=postgres://username:password@rds-endpoint:5432/database?sslmode=require
     ```
   - Auto-connects to RDS database (no manual login required)

5. **Update Security Groups**
   - Ensure ECS can reach RDS on port 5432
   - Update ALB target group health check path to `/`

### Success Criteria
- Access ALB DNS name in browser
- See pgweb interface automatically connected to RDS
- View database structure and tables
- Create tables and perform CRUD operations via web UI
- Execute SQL queries directly
- Database persists data across container restarts

### Example Configuration
```bash
# Test the deployment
curl http://<alb-dns-name>
# Expected: pgweb interface HTML

# Access in browser - automatically connected to PostgreSQL
# No login required, direct access to database

# Create a test table via SQL query:
CREATE TABLE users (
  id SERIAL PRIMARY KEY,
  name VARCHAR(100),
  email VARCHAR(100),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

# Insert test data
INSERT INTO users (name, email) VALUES 
  ('John Doe', 'john@example.com'),
  ('Jane Smith', 'jane@example.com');

# Query data
SELECT * FROM users;

# Verify data persists across ECS task restarts
```

---

## Exercise 3: Add Route53 + HTTPS with ACM Certificate

**Goal:** Add custom domain with HTTPS support

### Required Components
1. **Route53 Hosted Zone**
   - Create or use existing hosted zone
   - Example: `interview.example.com`

2. **ACM Certificate**
   - Request certificate for your domain
   - Validate via DNS (Route53)
   - Must be in the same region (eu-west-1)

3. **Route53 DNS Record**
   - Create A record (alias) pointing to ALB
   - Example: `app.interview.example.com` -> ALB

4. **Update ALB**
   - Add HTTPS listener on port 443
   - Attach ACM certificate
   - Configure SSL policy (recommend: ELBSecurityPolicy-TLS13-1-2-2021-06)
   - Optional: Redirect HTTP to HTTPS

5. **Update Security Groups**
   - Add HTTPS (443) ingress rule to ALB security group

### Success Criteria
- Access application via custom domain with HTTPS
- Valid SSL certificate (no browser warnings)
- HTTP redirects to HTTPS (if configured)
- Application fully functional over HTTPS

### Example Configuration
```bash
# Test HTTPS
curl https://app.interview.example.com
# Expected: Spring PetClinic homepage with valid SSL

# Test HTTP redirect (if configured)
curl -I http://app.interview.example.com
# Expected: 301/302 redirect to HTTPS
```

---

## Setup Instructions

### 1. Configure AWS Credentials

Set up your AWS credentials as environment variables:

```bash
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_DEFAULT_REGION="eu-west-1"
```

### 2. Initialize Terraform
```bash
tofu init
```

### 3. Plan Infrastructure
```bash
tofu plan
```

### 4. Apply Base Infrastructure
```bash
tofu apply
```

---

## Evaluation Criteria

Candidates will be evaluated on:

1. **Infrastructure as Code Best Practices**
   - Clean, readable code
   - Proper resource naming using tags
   - Use of variables and outputs
   - DRY principles

2. **Security**
   - Least privilege security groups
   - Private subnets for databases and applications
   - Encrypted storage
   - SSL/TLS configuration

3. **Networking**
   - Proper subnet placement
   - Security group rules
   - Load balancer configuration

4. **Problem Solving**
   - Debugging approach
   - Understanding of AWS services
   - Ability to troubleshoot issues

5. **Documentation**
   - Code comments where appropriate
   - Clear variable descriptions
   - Useful outputs

---

## Candidate Instructions

You can either:
- Use community modules (e.g., terraform-aws-modules)
- Create resources from scratch
- Mix both approaches

Focus on:
- Security best practices
- Proper networking configuration
- Resource dependencies
- Clean, readable code

---

## AWS Account Details
- Account: 105458107979
- State Bucket: dna-stag-terraform-state
- State Key: interview/terraform.tfstate
- Region: eu-west-1

---

## Time Allocation (Suggested)

- Exercise 1: 30-45 minutes
- Exercise 2: 30-45 minutes
- Exercise 3: 20-30 minutes
- Total: ~90 minutes

---

## Hints & Tips

### Exercise 1
- Start with security groups before creating ALB and ECS
- Remember Fargate requires `awsvpc` network mode
- Target type must be `ip` for Fargate

### Exercise 2
- RDS takes 5-10 minutes to provision
- pgweb auto-connects with connection string in command
- Test database connectivity by creating tables and inserting data

### Exercise 3
- ACM certificate validation can take a few minutes
- DNS propagation may take time
- Test with `dig` or `nslookup` to verify DNS records

---

## Troubleshooting

### ECS Tasks Not Starting
- Check CloudWatch logs: `/aws/ecs/dna-interview-ecs`
- Verify security groups allow required traffic
- Check NAT Gateway for private subnet internet access

### RDS Connection Issues
- Verify security group allows port 5432 from ECS
- Check RDS endpoint is correct
- Ensure database credentials are correct

### HTTPS Not Working
- Verify ACM certificate is validated and issued
- Check ALB listener configuration
- Ensure security group allows port 443

---

## Outputs

After completing each exercise, you should be able to retrieve:

```bash
# Exercise 1
tofu output alb_dns_name
tofu output ecs_cluster_name

# Exercise 2
tofu output rds_endpoint
tofu output rds_database_name

# Exercise 3
tofu output route53_record_name
tofu output acm_certificate_arn
```
