# AWS Infrastructure Interview Task

## Overview
This is a live coding interview exercise where candidates will create AWS infrastructure using Terraform/OpenTofu.

## Pre-created Resources (Provided)
- VPC with public/private subnets
- IAM roles for ECS tasks
- Base networking (Internet Gateway, Route Tables)

## Candidate Task
The candidate needs to create the following resources:

### Required Components
1. **ECS Cluster & Task Definition**
   - Use image: `bitnami/spring-cloud-dataflow`
   - Configure appropriate CPU/memory
   - Link to provided IAM roles

2. **RDS Instance**
   - PostgreSQL or MySQL
   - Deploy in private subnets
   - Configure security groups

3. **Application Load Balancer (ALB)**
   - Deploy in public subnets
   - Configure target group for ECS service
   - Set up health checks

4. **Route53**
   - Create DNS record pointing to ALB
   - Configure appropriate routing

5. **Security Groups**
   - ALB security group (allow HTTP/HTTPS)
   - ECS security group (allow traffic from ALB)
   - RDS security group (allow traffic from ECS)

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

## AWS Account Details
- Account: 105458107979
- State Bucket: dna-stag-terraform-state
- State Key: interview/terraform.tfstate
- Region: eu-west-1
