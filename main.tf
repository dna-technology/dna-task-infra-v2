terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
  
  backend "s3" {
    bucket         = "dna-stag-terraform-state"
    key            = "interview/terraform.tfstate"
    region         = "eu-west-1"
    encrypt        = true
    dynamodb_table = "dna-stag-terraform-locks"
  }
}

provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = module.this.tags
  }
}
