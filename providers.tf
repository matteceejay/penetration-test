# ---------------------------------------------------------------------
# AWS PROVIDER
# ---------------------------------------------------------------------
# default_tags applies these tags to every resource this provider creates
# that supports tagging. This satisfies the requirement to tag every
# resource with project, owner, purpose, and expiration date, without
# repeating (and possibly forgetting) it on every individual resource.
#
# The values are driven by variables, sourced from terraform.tfvars, so
# this same provider config is reusable for a future pentest engagement.
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project    = var.project_name
      Owner      = var.owner
      Purpose    = "penetration-testing"
      Expiration = var.expiration_date
      ManagedBy  = "terraform"
    }
  }
}