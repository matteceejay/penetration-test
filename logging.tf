
#   Satisfies "enable the required AWS and host logging so vendor activity
#   can be traced during the test." Covers three layers:
#     1. NETWORK  — VPC Flow Logs for the approved subnet, capturing every
#        connection to/from the instance.
#     2. HOST     — a CloudWatch Log Group that the CloudWatch agent
#        (configured in user_data.sh.tpl) ships auditd/auth logs into,
#        if enable_cloudwatch_agent = true.
#     3. SESSION  — if connection_method = "ssm", Session Manager logs are
#        additionally sent to CloudWatch so every interactive session
#        (commands typed, output shown) is recorded by AWS itself,
#        independent of anything running on the host.
#
#   NOTE: Account-level API auditing (CloudTrail) is intentionally NOT
#   created here. Most AWS accounts already have an org-wide or
#   account-wide CloudTrail trail running; creating a second, redundant
#   trail scoped to just this project adds cost and noise without adding
#   traceability. Confirm CloudTrail is already enabled for this account
#   before the engagement starts — if it isn't, that's an account-level
#   fix, not something this project should bolt on.



# 1. NETWORK: VPC Flow Logs for the approved subnet


resource "aws_cloudwatch_log_group" "flow_logs" {
  name              = "/pentest/${var.project_name}/vpc-flow-logs"
  retention_in_days = var.flow_log_retention_days
}

# Flow Logs need their own IAM role to write into CloudWatch Logs —
# separate from the EC2 instance role, since this is a different AWS
# service (the VPC Flow Logs service, not the instance) doing the writing.
data "aws_iam_policy_document" "flow_logs_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "flow_logs" {
  name               = "${var.project_name}-pentest-flow-logs-role"
  assume_role_policy = data.aws_iam_policy_document.flow_logs_assume_role.json
}

data "aws_iam_policy_document" "flow_logs_permissions" {
  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
    ]
    resources = ["${aws_cloudwatch_log_group.flow_logs.arn}:*"]
  }
}

resource "aws_iam_role_policy" "flow_logs" {
  name   = "${var.project_name}-pentest-flow-logs-policy"
  role   = aws_iam_role.flow_logs.id
  policy = data.aws_iam_policy_document.flow_logs_permissions.json
}

# Scoped to the SUBNET (not the whole VPC) since that's all this
# engagement's traffic touches — keeps the log volume relevant to just
# this project rather than the entire VPC's traffic.
resource "aws_flow_log" "pentest_subnet" {
  log_destination_type = "cloud-watch-logs"
  log_destination      = aws_cloudwatch_log_group.flow_logs.arn
  iam_role_arn         = aws_iam_role.flow_logs.arn
  subnet_id            = var.subnet_id
  traffic_type         = "ALL"

  tags = {
    Name = "${var.project_name}-pentest-flow-log"
  }
}


# 2. HOST: log group the CloudWatch agent ships auditd/auth logs into

# Name matches what's referenced inside templates/user_data.sh.tpl's
# CloudWatch agent config, so the two stay in sync.
resource "aws_cloudwatch_log_group" "host_logs" {
  count             = var.enable_cloudwatch_agent ? 1 : 0
  name              = "${var.project_name}-pentest-host-logs"
  retention_in_days = var.flow_log_retention_days
}


# 3. SESSION: SSM Session Manager logging, only relevant if using SSM

resource "aws_cloudwatch_log_group" "ssm_sessions" {
  count             = var.connection_method == "ssm" ? 1 : 0
  name              = "${var.project_name}-pentest-ssm-sessions"
  retention_in_days = var.flow_log_retention_days
}

# This document sets the ACCOUNT-WIDE default Session Manager preferences
# to log all session activity to the log group above. Because it's
# account-wide, applying this affects Session Manager logging for the
# whole account for as long as this project exists — call this out to
# your team before applying if other SSM usage exists in the account.
resource "aws_ssm_document" "session_manager_prefs" {
  count           = var.connection_method == "ssm" ? 1 : 0
  name            = "SSM-SessionManagerRunShell"
  document_type   = "Session"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "1.0"
    description   = "Pentest engagement session logging preferences"
    sessionType   = "Standard_Stream"
    inputs = {
      cloudWatchLogGroupName      = aws_cloudwatch_log_group.ssm_sessions[0].name
      cloudWatchEncryptionEnabled = true
      cloudWatchStreamingEnabled  = true
    }
  })
}
