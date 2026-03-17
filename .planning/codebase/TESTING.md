# Testing Patterns

**Analysis Date:** 2026-03-17

## Test Framework

**Runner:** None configured

This is a Terraform/OpenTofu infrastructure-as-code project with **no automated test framework** in place. There are no test files, no test configuration, and no CI/CD pipeline defined.

**No test-related files found:**
- No `*.test.*` or `*.spec.*` files
- No `jest.config.*`, `vitest.config.*`, or equivalent
- No `.github/workflows/` directory (no CI/CD)
- No `Makefile` for task automation
- No `.pre-commit-config.yaml` for pre-commit hooks
- No `terratest` (Go-based Terraform testing) configuration
- No `tftest` (native Terraform test) `.tftest.hcl` files
- No `checkov` or `tfsec` configuration files

## Current Validation Approach

**Manual only.** The project relies on:

1. **`tofu plan`** — preview infrastructure changes before applying
2. **`tofu validate`** — syntax and configuration validation
3. **`tofu fmt`** — formatting consistency check
4. **Variable validation blocks** — input validation in `context.tf`

### Variable Validation (only existing automated validation)

```hcl
# From context.tf lines 79-87
variable "context" {
  validation {
    condition     = lookup(var.context, "label_key_case", null) == null ? true : contains(["lower", "title", "upper"], var.context["label_key_case"])
    error_message = "Allowed values: `lower`, `title`, `upper`."
  }

  validation {
    condition     = lookup(var.context, "label_value_case", null) == null ? true : contains(["lower", "title", "upper", "none"], var.context["label_value_case"])
    error_message = "Allowed values: `lower`, `title`, `upper`, `none`."
  }
}
```

See also: `context.tf` lines 213-216 for `id_length_limit` validation, lines 229-232 for `label_key_case` validation, lines 247-250 for `label_value_case` validation.

## Run Commands

```bash
tofu init                # Initialize providers and backend
tofu validate            # Validate configuration syntax
tofu fmt -check          # Check formatting without modifying
tofu fmt                 # Auto-format all .tf files
tofu plan                # Preview changes (primary validation method)
tofu apply               # Apply infrastructure changes
```

## Recommended Testing Approach

The `STEERING.md` recommends security scanning but provides no implementation:

> "Static Analysis: Run tfsec or checkov before deployment"

### If Adding Tests, Use These Patterns:

**Option 1 — Native Terraform Tests (recommended for this project size):**

Create `.tftest.hcl` files in the project root:

```hcl
# vpc.tftest.hcl
run "vpc_creates_correct_subnets" {
  command = plan

  assert {
    condition     = length(aws_subnet.public) == 3
    error_message = "Expected 3 public subnets"
  }

  assert {
    condition     = length(aws_subnet.private) == 3
    error_message = "Expected 3 private subnets"
  }
}
```

Run with: `tofu test`

**Option 2 — tfsec for Security Scanning:**

```bash
# Install
brew install tfsec

# Run
tfsec .
```

**Option 3 — checkov for Policy Compliance:**

```bash
# Install
pip install checkov

# Run
checkov -d .
```

**Option 4 — Terratest (Go-based, for integration tests):**

Would require a `test/` directory with Go test files. Overkill for this interview project.

## Test File Organization

**Current:** No test files exist.

**If adding tests, place them as:**
```
project-root/
├── tests/                    # Native Terraform test directory (if using tofu test)
│   ├── vpc.tftest.hcl
│   ├── iam.tftest.hcl
│   └── setup.tfvars          # Test-specific variable values
├── vpc.tftest.hcl            # Alternative: co-located with source (also supported)
└── ...
```

## Coverage

**Requirements:** None enforced. No coverage tooling configured.

**Test coverage gaps (everything is untested):**
- VPC and subnet creation (`vpc.tf`)
- IAM role configuration (`iam-ecs.tf`)
- Provider and backend configuration (`main.tf`)
- Variable defaults and validation (`variables.tf`, `context.tf`)
- Output values (`outputs.tf`)

## Mocking

**Not applicable** — no tests exist. If using native Terraform tests, mock providers can be configured:

```hcl
# Example mock for testing without AWS credentials
mock_provider "aws" {}

run "plan_only_test" {
  command = plan
  # assertions here
}
```

## CI/CD Pipeline

**None configured.** No `.github/workflows/`, `Jenkinsfile`, `.gitlab-ci.yml`, `bitbucket-pipelines.yml`, or any other CI configuration exists.

**If adding CI, a minimal GitHub Actions workflow would look like:**

```yaml
name: Terraform Validate
on: [pull_request]
jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: opentofu/setup-opentofu@v1
      - run: tofu init -backend=false
      - run: tofu fmt -check
      - run: tofu validate
```

## Pre-commit Hooks

**None configured.** No `.pre-commit-config.yaml` exists.

**If adding pre-commit hooks:**
```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/antonbabenko/pre-commit-terraform
    rev: v1.88.0
    hooks:
      - id: terraform_fmt
      - id: terraform_validate
      - id: terraform_tfsec
```

## Quality Gates Summary

| Gate | Status | Tool |
|------|--------|------|
| Formatting | Manual (`tofu fmt`) | OpenTofu built-in |
| Syntax validation | Manual (`tofu validate`) | OpenTofu built-in |
| Input validation | Partial (context vars only) | HCL `validation` blocks |
| Security scanning | Not configured | Recommended: tfsec/checkov |
| Unit tests | Not configured | Recommended: `tofu test` |
| Integration tests | Not configured | N/A for interview project |
| CI/CD | Not configured | Recommended: GitHub Actions |
| Pre-commit hooks | Not configured | Recommended: pre-commit-terraform |

---

*Testing analysis: 2026-03-17*
