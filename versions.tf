# ######    Terraform Version and Remote Backend    #######
#
# Internal-facing — the vendor has no control over which Terraform
# version is used or where the state file is stored. That's the
# company's decision.
#
# A dedicated S3 backend is good practice: it can never accidentally
# get mixed into the company's main infrastructure state file, it's
# easy to clean up (destroying this project can't affect unrelated
# resources), and anyone on the team can pick up remediation/teardown
# later since state isn't sitting on one person's laptop.
terraform {
  # use_lockfile (native S3 locking, no DynamoDB table needed) requires
  # Terraform 1.10 or newer.
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket       = "test-penetration-handart.site"
    key          = "pentest-environment/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}