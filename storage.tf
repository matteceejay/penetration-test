
#   Satisfies "provide encrypted storage for tools and test output, plus
#   enough CPU, memory, and disk space for the engagement" (the storage
#   half — CPU/memory come from var.instance_type in ec2.tf).
#
#   Two volumes exist on the instance:
#     - The ROOT volume (defined in ec2.tf as a root_block_device),
#       encrypted, sized by var.root_volume_size_gb.
#     - A dedicated DATA volume defined here, mounted at /data, meant to
#       hold tester tools and scan/test output separately from the OS
#       disk. Keeping it separate makes it trivial to snapshot just the
#       test evidence before teardown, without dealing with OS files.


# Dedicated KMS key for this engagement only, so encryption for this
# environment isn't tangled up with keys used elsewhere in the account.
# Only created if you didn't supply an existing key via var.kms_key_id.
# Having a dedicated key also makes teardown cleaner: you can schedule
# this key for deletion once the engagement's evidence has been copied
# out and no longer needs decrypting.
resource "aws_kms_key" "pentest_data" {
  count                   = var.kms_key_id == null ? 1 : 0
  description             = "Encryption key for ${var.project_name} pentest engagement EBS volumes"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Name = "${var.project_name}-pentest-kms-key"
  }
}

resource "aws_kms_alias" "pentest_data" {
  count         = var.kms_key_id == null ? 1 : 0
  name          = "alias/${var.project_name}-pentest"
  target_key_id = aws_kms_key.pentest_data[0].key_id
}

# Resolves to whichever key applies: the one you supplied, or the one
# created above.
locals {
  kms_key_id_effective = coalesce(var.kms_key_id, try(aws_kms_key.pentest_data[0].arn, null))
}

# The dedicated, encrypted volume for tester tools and test output.
# Placed in the same AZ as the subnet so it can attach to the instance.
resource "aws_ebs_volume" "tester_data" {
  availability_zone = data.aws_subnet.approved.availability_zone
  size              = var.data_volume_size_gb
  type              = "gp3"
  encrypted         = true
  kms_key_id        = local.kms_key_id_effective

  tags = {
    Name = "${var.project_name}-pentest-data-volume"
  }
}

resource "aws_volume_attachment" "tester_data" {
  device_name = "/dev/xvdf"
  volume_id   = aws_ebs_volume.tester_data.id
  instance_id = aws_instance.pentest.id
}