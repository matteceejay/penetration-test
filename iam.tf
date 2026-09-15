
#   Satisfies "attach an EC2 instance profile with the least-privilege IAM
#   role required for the agreed AWS testing scope."
#
#   The role has:
#     1. A trust policy allowing only EC2 to assume it.
#     2. An inline policy scoped EXACTLY to var.allowed_aws_actions /
#        var.allowed_aws_resources — i.e. whatever the rules of engagement
#        actually authorize, nothing more. These variables ship with
#        obvious placeholder values on purpose so this project will not
#        silently apply with real (over-broad) access.
#     3. The AWS-managed SSM policy attached ONLY if connection_method is
#        "ssm", since that's what allows Session Manager to reach the box.


# Trust policy: only the EC2 service can assume this role (standard for an
# instance profile — nothing else should be able to use these credentials).



data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "pentest_instance_role" {
  name               = "${var.project_name}-pentest-instance-role"
  description        = "Least-privilege role for the temporary pentest EC2 instance, scoped to the agreed testing rules of engagement."
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

# The actual least-privilege policy. allowed_aws_actions/resources come
# straight from tfvars — this is the piece that most directly needs the
# vendor's confirmed scope before you apply for real. Shipping with
# placeholder values means `terraform plan` will work end-to-end today,
# but `terraform apply` should not be run against a real AWS account until
# these are replaced with the actual approved scope.



data "aws_iam_policy_document" "pentest_scope" {
  dynamic "statement" {
    for_each = var.iam_policy_statements
    content {
      sid       = statement.value.sid
      actions   = statement.value.actions
      resources = statement.value.resources
    }
  }
}

resource "aws_iam_role_policy" "pentest_scope" {
  name   = "${var.project_name}-pentest-scope"
  role   = aws_iam_role.pentest_instance_role.id
  policy = data.aws_iam_policy_document.pentest_scope.json
}

# Only attached when using SSM as the connection method — grants the
# managed permissions Session Manager needs to establish a session with
# this instance. This does NOT grant any access beyond connectivity itself
# (it's not a broad admin policy); the actual testing scope is still
# bounded by the inline policy above.




resource "aws_iam_role_policy_attachment" "ssm_core" {
  count      = var.connection_method == "ssm" ? 1 : 0
  role       = aws_iam_role.pentest_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Only attached when the CloudWatch agent is enabled — lets the agent on
# the instance push OS-level logs/metrics to CloudWatch without needing
# broader permissions.

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  count      = var.enable_cloudwatch_agent ? 1 : 0
  role       = aws_iam_role.pentest_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# The instance profile is the actual object an EC2 instance attaches to;
# it's just a thin wrapper around the role above.


resource "aws_iam_instance_profile" "pentest_instance_profile" {
  name = "${var.project_name}-pentest-instance-profile"
  role = aws_iam_role.pentest_instance_role.name
}