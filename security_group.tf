

#   Satisfies "limit inbound or session access to the approved vendor
#   connection method and source addresses."
#
#   Only created when connection_method = "ssh". If connection_method =
#   "ssm", NO security group / inbound rule is needed at all — Session
#   Manager works entirely over outbound HTTPS (443) from the instance to
#   the SSM service, so there is nothing to open inbound. That's a big part
#   of why SSM is the preferred method for a pentest jump box.



resource "aws_security_group" "pentest_instance" {
  count = var.connection_method == "ssh" ? 1 : 0

  name        = "${var.project_name}-pentest-sg"
  description = "Restricts inbound access to the pentest instance to the vendor's approved source IPs only."
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.project_name}-pentest-sg"
  }
}

# Inbound SSH, restricted to the exact CIDR ranges the vendor confirmed in
# writing. var.allowed_source_cidrs has no default, so Terraform will
# refuse to apply with an empty/wildcard list left in unless you fill it
# in in tfvars — that's intentional, to prevent accidentally shipping a
# 0.0.0.0/0 rule.
resource "aws_vpc_security_group_ingress_rule" "ssh_from_vendor" {
  for_each = var.connection_method == "ssh" ? toset(var.allowed_source_cidrs) : []

  security_group_id = aws_security_group.pentest_instance[0].id
  description        = "SSH from approved vendor source IP"
  from_port          = 22
  to_port            = 22
  ip_protocol        = "tcp"
  cidr_ipv4          = each.value
}

# Outbound: the instance needs to reach out to install approved packages,
# pull tester scripts, and (if enabled) ship logs to CloudWatch/SSM. Kept
# open on egress since inbound is the side that actually needs restricting
# for a jump box like this — tighten to specific destinations (e.g. your
# package mirror, AWS service endpoints) if your environment requires it.
resource "aws_vpc_security_group_egress_rule" "all_outbound" {
  count = var.connection_method == "ssh" ? 1 : 0

  security_group_id = aws_security_group.pentest_instance[0].id
  description        = "Allow all outbound traffic"
  ip_protocol        = "-1"
  cidr_ipv4          = "0.0.0.0/0"
}