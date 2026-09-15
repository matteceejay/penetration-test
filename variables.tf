
#   Declares every input this project needs. None of the actual values live
#   here — this file only defines the "shape" (type, description, and a
#   safe default where one makes sense). The real values go in
#   terraform.tfvars, which is where all of the still-unanswered vendor
#   questions will ultimately be filled in.
#
#   Variables with `default = null` or an obvious placeholder string have
#   NO safe default — Terraform will use whatever you put in
#   terraform.tfvars. Variables with a real default (like volume size) are
#   ones you can reasonably start with and adjust once the vendor confirms
#   specifics.

##### ACCOUNT / TAGGING CONTEX  #####

variable "aws_region" {
  description = "AWS region to deploy the pentest environment into. Must match the region of the approved VPC/subnet."
  type        = string
}

variable "project_name" {
  description = "Short name used for tagging and resource naming, e.g. \"pentest-2026-q3\". Used in the mandatory Project tag."
  type        = string
}

variable "owner" {
  description = "Person accountable for this environment (you, as lead engineer). Used in the mandatory Owner tag."
  type        = string
}

variable "expiration_date" {
  description = "Planned teardown date for this environment, e.g. \"2026-10-15\". Used in the mandatory Expiration tag so anyone auditing the account can see this is temporary and when it should be gone."
  type        = string
}

# NETWORK PLACEMENT  (open question: which VPC and subnet should host it?)

variable "vpc_id" {
  description = "ID of the APPROVED VPC the pentest instance must be deployed into. This must come from whoever owns network approval, not be guessed — it determines what the instance can reach."
  type        = string
}

variable "subnet_id" {
  description = "ID of the APPROVED SUBNET within vpc_id. Prefer a private subnet with outbound-only internet access (via NAT Gateway) unless the vendor specifically requires a public IP."
  type        = string
}

variable "assign_public_ip" {
  description = "Whether the instance gets a public IP. Should almost always be false — the vendor should reach the box through the approved connection method (SSH via bastion, or SSM Session Manager), not a public IP directly. Only set true if network/security explicitly approves it."
  type        = bool
  default     = false
}

# INSTANCE SIZING / OS  (open questions: which Linux distro, which instance type?)

variable "os_family" {
  description = "Which Linux distribution to launch. Supported: \"amazon-linux-2023\", \"ubuntu-22.04\", \"rhel-9\". Drives the AMI lookup in data.tf. Confirm with the vendor which distro their tooling expects."
  type        = string
  default     = "amazon-linux-2023"

  validation {
    condition     = contains(["amazon-linux-2023", "ubuntu-22.04", "rhel-9"], var.os_family)
    error_message = "os_family must be one of: amazon-linux-2023, ubuntu-22.04, rhel-9."
  }
}

variable "ami_id_override" {
  description = "Optional: hardcode a specific AMI ID instead of using the os_family lookup. Leave as null to auto-select the latest AMI for os_family. Set this if the vendor requires a specific, pre-approved/hardened image."
  type        = string
  default     = null
}

variable "instance_type" {
  description = "EC2 instance type approved for the engagement, e.g. \"t3.large\". Sizing should reflect what the vendor's tooling needs (memory-heavy scanners, brute-force tooling, etc.) — confirm with the vendor rather than guessing."
  type        = string
}

# CONNECTIVITY  (open questions: SSH or SSM? which source IPs?)

variable "connection_method" {
  description = "How the vendor will connect to the instance: \"ssh\" or \"ssm\". SSM (Session Manager) is generally preferred for pentest boxes because it needs no open inbound port and every session is logged by AWS by default. Only use \"ssh\" if the vendor's tooling specifically requires it."
  type        = string

  validation {
    condition     = contains(["ssh", "ssm"], var.connection_method)
    error_message = "connection_method must be either \"ssh\" or \"ssm\"."
  }
}

variable "allowed_source_cidrs" {
  description = "List of CIDR blocks allowed to reach the instance on the SSH port (only used when connection_method = \"ssh\"). MUST be the vendor's actual, confirmed source IP ranges — never 0.0.0.0/0. Get this in writing from the vendor before applying."
  type        = list(string)
  default     = []
}

variable "ssh_public_key" {
  description = "Public key material (contents of an id_ed25519.pub / id_rsa.pub file) used to create the AWS key pair, if connection_method = \"ssh\". Leave empty if using SSM."
  type        = string
  default     = ""
  sensitive   = false
}

# TESTERS  (open question: how many testers, what auth method each?)

variable "testers" {
  description = <<-EOT
    List of individual testers who need their own OS account on the
    instance, satisfying "create an individual operating system account
    for each tester and provide an approved authentication method."

    Each object:
      username   - Linux username to create for this tester (no spaces).
      public_key - SSH public key for this tester's individual login.
                   Required if connection_method = "ssh". Can be left ""
                   if connection_method = "ssm" (testers will connect via
                   SSM and `sudo su - <username>` into their own account;
                   see README for the access-control note on this).

    Example:
      testers = [
        { username = "vendor_jsmith", public_key = "ssh-ed25519 AAAA... jsmith" },
        { username = "vendor_agupta", public_key = "ssh-ed25519 AAAA... agupta" },
      ]
  EOT
  type = list(object({
    username   = string
    public_key = optional(string, "")
  }))
  default = []
}

# PACKAGES  (open question: what's on the "approved packages" list?)

variable "approved_packages" {
  description = "OS packages to preinstall via the OS package manager (yum/dnf or apt, depending on os_family) so testers don't need broader install rights than necessary. This is informational/config only — it does not by itself restrict what testers CAN install if they have sudo; pair it with the sudoers policy in the README if you need to hard-enforce a package allowlist."
  type        = list(string)
  default     = []
}

# STORAGE  (open question: how much disk space is required?)

variable "root_volume_size_gb" {
  description = "Root (OS) volume size in GiB."
  type        = number
  default     = 30
}

variable "data_volume_size_gb" {
  description = "Size in GiB of the dedicated, encrypted EBS volume used for tester tools and test output (mounted at /data). Confirm with the vendor how much scan output / capture data they expect to generate."
  type        = number
  default     = 100
}

variable "kms_key_id" {
  description = "Optional: ARN/ID of an existing KMS key to use for encrypting the EBS volumes. Leave null to have this project create a dedicated KMS key just for this engagement (recommended, since it can be disabled/scheduled for deletion cleanly at teardown)."
  type        = string
  default     = null
}

# IAM SCOPE  (open question: exactly which AWS services can testers touch?)

variable "iam_policy_statements" {
  description = <<-EOT
    List of IAM policy statements scoped to the agreed testing rules of
    engagement. Each statement pairs its own actions with its own
    resources, so different AWS services in scope (S3, EC2, RDS, etc.)
    can each get the exact access level and target ARNs they need,
    without accidentally cross-applying one service's actions to
    another service's resources.

    Fill this in once the vendor confirms exactly which resources they
    will be scanning and what access each requires.

    Example:
      iam_policy_statements = [
        {
          sid       = "S3ReadOnlyScopedBuckets"
          actions   = ["s3:ListBucket", "s3:GetObject"]
          resources = ["arn:aws:s3:::approved-test-bucket", "arn:aws:s3:::approved-test-bucket/*"]
        },
        {
          sid       = "EC2DescribeOnly"
          actions   = ["ec2:DescribeInstances", "ec2:DescribeSecurityGroups"]
          resources = ["*"] # describe-type actions generally can't be scoped to a specific ARN
        },
      ]
  EOT
  type = list(object({
    sid       = string
    actions   = list(string)
    resources = list(string)
  }))
  default = [
    {
      sid       = "REPLACE_ME_PENDING_VENDOR_SCOPE"
      actions   = ["REPLACE_ME_WITH_APPROVED_ACTIONS"]
      resources = ["REPLACE_ME_WITH_APPROVED_RESOURCE_ARNS"]
    }
  ]
}
variable "allowed_aws_resources" {
  description = "List of resource ARNs the allowed_aws_actions apply to. Should be as narrow as possible — specific bucket ARNs, specific instance ARNs, etc. — not \"*\", unless the rules of engagement genuinely authorize account-wide read access."
  type        = list(string)
  default     = ["REPLACE_ME_WITH_APPROVED_RESOURCE_ARNS"]
}

# LOGGING

variable "flow_log_retention_days" {
  description = "How many days to retain VPC Flow Logs (network traffic to/from the instance) in CloudWatch Logs, satisfying the 'enable required AWS logging so vendor activity can be traced' requirement."
  type        = number
  default     = 90
}

variable "enable_cloudwatch_agent" {
  description = "Whether to install and configure the CloudWatch agent on the instance to ship OS-level logs (auth logs, auditd, bash history) to CloudWatch Logs, in addition to AWS-side logging (VPC Flow Logs / SSM session logs). Recommended true for full traceability of vendor activity on the host itself."
  type        = bool
  default     = true
}