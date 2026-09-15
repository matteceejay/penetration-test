
#   Read-only lookups against things that already exist in the account:
#     - The approved VPC and subnet (we never CREATE network resources
#       here — the vendor requirement says "deploy into the approved VPC
#       and subnet", implying networking is pre-existing and pre-approved).
#     - The correct AMI for whichever Linux distro os_family selects.


# Confirms the VPC ID you supplied in tfvars actually exists and is
# reachable by this account/region. Also lets other resources (like the
# flow log) reference its ID/attributes without hardcoding.
data "aws_vpc" "approved" {
  id = var.vpc_id
}

# Same idea for the subnet: validates it exists and belongs to the VPC
# above, and exposes its availability zone/CIDR for reference if needed.
data "aws_subnet" "approved" {
  id = var.subnet_id
}


# AMI LOOKUPS

# We look up the AMI via SSM Public Parameters / owner+name filters rather
# than hardcoding an AMI ID, because AMI IDs are region-specific and are
# replaced regularly with patched versions. Only one of these data sources
# is actually used, selected by var.os_family (see local.selected_ami_id
# below). If var.ami_id_override is set, none of these matter — the
# override wins.

# Amazon Linux 2023 — published as an SSM public parameter, always current.
data "aws_ssm_parameter" "amazon_linux_2023" {
  count = var.os_family == "amazon-linux-2023" ? 1 : 0
  name  = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# Ubuntu 22.04 LTS — official Canonical AMIs, filtered by name pattern.
data "aws_ami" "ubuntu_22_04" {
  count       = var.os_family == "ubuntu-22.04" ? 1 : 0
  most_recent = true
  owners      = ["099720109477"] # Canonical's official AWS account ID

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# RHEL 9 — official Red Hat AMIs, filtered by name pattern.
data "aws_ami" "rhel_9" {
  count       = var.os_family == "rhel-9" ? 1 : 0
  most_recent = true
  owners      = ["309956199498"] # Red Hat's official AWS account ID

  filter {
    name   = "name"
    values = ["RHEL-9*_HVM-*-x86_64-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Picks whichever AMI ID applies based on os_family, unless an explicit
# override was provided in tfvars. Centralized here so ec2.tf just
# references local.selected_ami_id and doesn't need to know about the
# lookups above.
locals {
  selected_ami_id = coalesce(
    var.ami_id_override,
    try(data.aws_ssm_parameter.amazon_linux_2023[0].value, null),
    try(data.aws_ami.ubuntu_22_04[0].id, null),
    try(data.aws_ami.rhel_9[0].id, null),
  )
}