# Context variables for naming
namespace   = "dna"
environment = "interview"
name        = "ecs"

# Additional tags
tags = {
  ManagedBy = "terraform"
  Purpose   = "interview-exercise"
}

# AWS Configuration
aws_region = "eu-west-1"

# Network Configuration
vpc_cidr           = "10.64.0.0/20"
availability_zones = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
