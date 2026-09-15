
#   The pentest instance itself, satisfying:
#     - "Deploy a Linux EC2 instance in the approved VPC and subnet."
#     - "...provide enough CPU, memory, and disk space for the engagement"
#       (CPU/memory via instance_type, disk via root_block_device + the
#       separate data volume in storage.tf).
#     - "Allow the testers to install approved packages, copy their
#       scripts to the instance, and execute those scripts" — handled by
#       giving testers real shell accounts (via user_data) rather than a
#       locked-down non-interactive setup.


# Only created when connection_method = "ssh" and a public key was
# supplied — this is the key pair used for the initial/admin login, not
# the individual tester keys (those are installed directly into each
# tester's authorized_keys by user_data.sh.tpl).
resource "aws_key_pair" "admin" {
  count      = var.connection_method == "ssh" && var.ssh_public_key != "" ? 1 : 0
  key_name   = "${var.project_name}-pentest-admin-key"
  public_key = var.ssh_public_key
}

resource "aws_instance" "pentest" {
  ami           = local.selected_ami_id
  instance_type = var.instance_type

  # Approved network placement — never guessed, always from tfvars.
  subnet_id                   = var.subnet_id
  associate_public_ip_address = var.assign_public_ip

  # Only attaches a security group when using SSH; SSM needs none.
  vpc_security_group_ids = var.connection_method == "ssh" ? [aws_security_group.pentest_instance[0].id] : null

  # Only attaches an SSH key pair when one was created above.
  key_name = var.connection_method == "ssh" && var.ssh_public_key != "" ? aws_key_pair.admin[0].key_name : null

  # Least-privilege instance profile from iam.tf.
  iam_instance_profile = aws_iam_instance_profile.pentest_instance_profile.name

  # Enforce IMDSv2 (session-token-required metadata access) — standard
  # hardening step that prevents SSRF-style credential theft, especially
  # relevant on a box specifically used for offensive security tooling.
  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  # Detailed (1-minute) monitoring, feeding into the traceability
  # requirement alongside VPC Flow Logs and host-level logging.
  monitoring = true

  # Root/OS volume — encrypted, sized from tfvars.
  root_block_device {
    volume_size = var.root_volume_size_gb
    volume_type = "gp3"
    encrypted   = true
    kms_key_id  = local.kms_key_id_effective
  }

  # Bootstraps the OS: installs approved packages, creates one account per
  # tester, mounts the encrypted data volume, and turns on auditing. See
  # templates/user_data.sh.tpl for the full script.
  user_data = templatefile("${path.module}/templates/user_data.sh.tpl", {
    approved_packages      = join(" ", var.approved_packages)
    testers_json            = jsonencode(var.testers)
    data_device             = "/dev/xvdf"
    enable_cloudwatch_agent = var.enable_cloudwatch_agent
    project_name            = var.project_name
  })

  tags = {
    Name = "${var.project_name}-pentest-instance"
  }
}