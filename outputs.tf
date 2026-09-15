
#   Surfaces the handful of values you (or a teammate) will actually need
#   after `terraform apply` — to hand the vendor connection details, to
#   verify what got created, and to reference during remediation/teardown.

output "instance_id" {
  description = "EC2 instance ID of the pentest box."
  value       = aws_instance.pentest.id
}

output "instance_private_ip" {
  description = "Private IP of the pentest box — what you'll give the vendor if they're connecting via SSH from within an approved network path (e.g. VPN/bastion)."
  value       = aws_instance.pentest.private_ip
}

output "instance_public_ip" {
  description = "Public IP, only populated if assign_public_ip = true."
  value       = aws_instance.pentest.public_ip
}

output "connection_method" {
  description = "Reminder of which connection method this environment was built for."
  value       = var.connection_method
}

output "ssm_connect_command" {
  description = "AWS CLI command to start an SSM session, if connection_method = \"ssm\"."
  value       = var.connection_method == "ssm" ? "aws ssm start-session --target ${aws_instance.pentest.id}" : "N/A (connection_method is not ssm)"
}

output "security_group_id" {
  description = "Security group ID, if connection_method = \"ssh\"."
  value       = var.connection_method == "ssh" ? aws_security_group.pentest_instance[0].id : null
}

output "iam_role_arn" {
  description = "ARN of the least-privilege role attached to the instance — useful when confirming scope with the vendor or during a security review."
  value       = aws_iam_role.pentest_instance_role.arn
}

output "kms_key_arn" {
  description = "KMS key used to encrypt the instance's volumes."
  value       = local.kms_key_id_effective
}

output "data_volume_id" {
  description = "EBS volume ID holding tester tools/output — the thing to snapshot before teardown if you need to preserve evidence."
  value       = aws_ebs_volume.tester_data.id
}

output "flow_log_group_name" {
  description = "CloudWatch Log Group name containing VPC Flow Logs for this instance's subnet."
  value       = aws_cloudwatch_log_group.flow_logs.name
}