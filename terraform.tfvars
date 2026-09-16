##############################################################################
# terraform.tfvars
#
# This is the ONE file you should expect to keep editing as the vendor
# answers open questions. Every value below is a placeholder — nothing
# here is safe to apply as-is. Each block below is grouped by the
# still-unanswered question it corresponds to from the kickoff.
#
# Do not commit real vendor IPs, real account IDs, or anything sensitive
# to a public/shared repo without checking your org's policy first.
##############################################################################

# ---------------------------------------------------------------------
# Account / tagging context — you likely already know these.
# ---------------------------------------------------------------------
aws_region      = "REPLACE_ME"        # e.g. "us-east-1"
project_name    = "REPLACE_ME"        # e.g. "pentest-2026-q3"
owner           = "REPLACE_ME"        # e.g. "Matthew Oguguo"
expiration_date = "REPLACE_ME"        # e.g. "2026-10-15"

# ---------------------------------------------------------------------
# OPEN QUESTION: "which VPC and subnet should host the instance?"
# ---------------------------------------------------------------------
vpc_id           = "REPLACE_ME"       # e.g. "vpc-0123456789abcdef0"
subnet_id        = "REPLACE_ME"       # e.g. "subnet-0123456789abcdef0"
assign_public_ip = false              # leave false unless network approval says otherwise

# ---------------------------------------------------------------------
# OPEN QUESTION: "which Linux distribution should be used?"
# ---------------------------------------------------------------------
os_family       = "amazon-linux-2023" # or "ubuntu-22.04" / "rhel-9"
ami_id_override = null                # set to a specific AMI ID only if the vendor requires a pre-approved image

# ---------------------------------------------------------------------
# OPEN QUESTION: "what EC2 instance type is approved?"
# ---------------------------------------------------------------------
instance_type = "REPLACE_ME"          # e.g. "t3.large" — confirm sizing against the vendor's tooling needs

# ---------------------------------------------------------------------
# OPEN QUESTION: "will the vendor connect through SSH or SSM?"
#                "what source IP addresses should be allowed?"
# ---------------------------------------------------------------------
connection_method    = "REPLACE_ME"   # "ssh" or "ssm" — SSM is preferred if the vendor's tooling allows it
allowed_source_cidrs = []             # ONLY used if connection_method = "ssh". e.g. ["203.0.113.10/32"] — get this in writing from the vendor
ssh_public_key        = ""            # ONLY used if connection_method = "ssh". Paste the admin/bastion public key here

# ---------------------------------------------------------------------
# Individual tester OS accounts + their auth method.
# Add one object per tester once the vendor provides names/keys.
# Leave public_key = "" per-tester if connection_method = "ssm".
# ---------------------------------------------------------------------
testers = [
  # {
  #   username   = "REPLACE_ME"       # e.g. "vendor_jsmith"
  #   public_key = "REPLACE_ME"       # e.g. "ssh-ed25519 AAAA... jsmith"
  # },
]

# ---------------------------------------------------------------------
# Approved package list — confirm exactly what tooling the vendor needs
# preinstalled vs. what they'll bring/compile themselves.
# ---------------------------------------------------------------------
approved_packages = [
  # "REPLACE_ME_PACKAGE_NAME",
]

# ---------------------------------------------------------------------
# OPEN QUESTION: "how much storage is required?"
# ---------------------------------------------------------------------
root_volume_size_gb = 30              # OS volume — 30 GB is usually plenty unless tooling is unusually large
data_volume_size_gb = 100             # tools/output volume — confirm against expected scan/capture volume
kms_key_id           = null           # leave null to auto-create a dedicated key for this engagement


# ---------------------------------------------------------------------
# OPEN QUESTION: "exactly which resources will the vendor be scanning,
# and what access does each require?" — this drives the IAM policy.
# Add one statement per distinct service/access-level combination once
# the vendor confirms. Do not apply with the placeholder left in.
# ---------------------------------------------------------------------
iam_policy_statements = [
  {
    sid       = "REPLACE_ME_PENDING_VENDOR_SCOPE"
    actions   = ["REPLACE_ME_WITH_APPROVED_ACTIONS"]
    resources = ["REPLACE_ME_WITH_APPROVED_RESOURCE_ARNS"]
  },
]
allowed_aws_resources = [
  # "REPLACE_ME_WITH_APPROVED_RESOURCE_ARNS", e.g. "arn:aws:s3:::approved-test-bucket"
]

# ---------------------------------------------------------------------
# Logging — reasonable defaults, adjust retention if your org has a
# different standard for engagement records.
# ---------------------------------------------------------------------
flow_log_retention_days = 90
enable_cloudwatch_agent  = true