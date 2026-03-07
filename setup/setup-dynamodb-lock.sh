#!/bin/bash
set -e

REGION="eu-west-1"
TABLE_NAME="dna-stag-terraform-locks"

echo "Creating DynamoDB table for Terraform state locking..."
echo "Region: ${REGION}"
echo "Table: ${TABLE_NAME}"
echo ""

aws dynamodb create-table \
  --table-name ${TABLE_NAME} \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region ${REGION} \
  --tags Key=Purpose,Value=dna-stag-terraform-locks Key=Environment,Value=interview

echo ""
echo "✓ DynamoDB table created successfully!"
echo ""
echo "Waiting for table to become active..."
aws dynamodb wait table-exists --table-name ${TABLE_NAME} --region ${REGION}

echo "✓ Table is active and ready to use"
echo ""
echo "You can now run: tofu plan"
