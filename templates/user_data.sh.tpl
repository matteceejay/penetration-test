#!/bin/bash


#   This will run once on first boot of the pentest instance. Handles everything
#   that needs to happen INSIDE the OS, which Terraform itself can't do:
#     - install the approved package list
#     - create one Linux user account per tester (individual OS accounts)
#     - set up each tester's SSH key, if connection_method = "ssh"
#     - format + mount the dedicated encrypted data volume at /data, with
#       a private subdirectory per tester for tools/output
#     - turn on command-level auditing (auditd) so tester activity on the
#       host itself is traceable, not just network-level activity
#     - optionally install/configure the CloudWatch agent to ship those
#       logs off the box
#
#   Terraform fills in the $${...} placeholders below via `templatefile()`
#   in ec2.tf before this is passed to AWS as EC2 user data.
set -euo pipefail
exec > /var/log/user-data.log 2>&1
echo "=== Pentest environment bootstrap starting: $(date -u) ==="

# ---------------------------------------------------------------------
# 1. Package manager detection + approved package install
# ---------------------------------------------------------------------
if command -v dnf >/dev/null 2>&1; then
  PKG_INSTALL="dnf install -y"
elif command -v yum >/dev/null 2>&1; then
  PKG_INSTALL="yum install -y"
elif command -v apt-get >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  PKG_INSTALL="apt-get install -y"
else
  echo "Unsupported distro — no known package manager found." >&2
  exit 1
fi

# Baseline tooling every tester environment needs regardless of the
# vendor's specific package list: auditd for command logging.
$PKG_INSTALL audit || true

# Vendor/approved package list, injected from var.approved_packages.
# Left as a loop (rather than one install command) so one bad package
# name doesn't necessarily fail the whole list.
APPROVED_PACKAGES="${approved_packages}"
for pkg in $APPROVED_PACKAGES; do
  echo "Installing approved package: $pkg"
  $PKG_INSTALL "$pkg" || echo "WARNING: failed to install $pkg — check package name/repo availability" >&2
done

# ---------------------------------------------------------------------
# 2. Format + mount the dedicated encrypted data volume at /data
# ---------------------------------------------------------------------
DATA_DEVICE="${data_device}"
# Wait briefly for the volume attachment to show up in the OS.
for i in $(seq 1 30); do
  [ -e "$DATA_DEVICE" ] && break
  sleep 2
done

if [ -e "$DATA_DEVICE" ]; then
  # Only format if it doesn't already have a filesystem (idempotent across reboots).
  if ! blkid "$DATA_DEVICE" >/dev/null 2>&1; then
    mkfs -t ext4 "$DATA_DEVICE"
  fi
  mkdir -p /data
  mount "$DATA_DEVICE" /data
  echo "$DATA_DEVICE /data ext4 defaults,nofail 0 2" >> /etc/fstab
  chmod 755 /data
else
  echo "WARNING: data volume device $DATA_DEVICE not found — skipping mount." >&2
fi

# ---------------------------------------------------------------------
# 3. Create one OS account per tester + their own /data subdirectory
# ---------------------------------------------------------------------
# TESTERS_JSON is a JSON array like:
#   [{"username":"vendor_jsmith","public_key":"ssh-ed25519 AAAA..."}]
# injected from var.testers via jsonencode() in ec2.tf.
TESTERS_JSON='${testers_json}'

echo "$TESTERS_JSON" | python3 -c '
import json, sys
for t in json.load(sys.stdin):
    print(t["username"] + "\t" + t.get("public_key",""))
' | while IFS=$'"'"'\t'"'"' read -r username public_key; do
  [ -z "$username" ] && continue
  echo "Creating tester account: $username"

  if ! id "$username" >/dev/null 2>&1; then
    useradd -m -s /bin/bash "$username"
  fi

  # Individual SSH key, only relevant when connection_method = "ssh".
  if [ -n "$public_key" ]; then
    home_dir="/home/$username"
    mkdir -p "$home_dir/.ssh"
    echo "$public_key" > "$home_dir/.ssh/authorized_keys"
    chmod 700 "$home_dir/.ssh"
    chmod 600 "$home_dir/.ssh/authorized_keys"
    chown -R "$username:$username" "$home_dir/.ssh"
  fi

  # Each tester gets their own private subdirectory under /data for
  # tools and output, rather than one shared free-for-all directory.
  if [ -d /data ]; then
    mkdir -p "/data/$username"
    chown "$username:$username" "/data/$username"
    chmod 700 "/data/$username"
  fi

  # NOTE: no sudo access granted by default. If specific testers need
  # elevated rights for their tooling, add them to an appropriate group
  # explicitly and document why, rather than granting broad sudo.
done

# ---------------------------------------------------------------------
# 4. Command-level auditing, so activity on the host is traceable
# ---------------------------------------------------------------------
systemctl enable auditd || true
systemctl start auditd || true
# Log execve calls (i.e. every command run) — gives you an audit trail of
# tester activity on the host independent of shell history, which testers
# could otherwise clear.
echo "-a always,exit -F arch=b64 -S execve -k tester_commands" >> /etc/audit/rules.d/pentest.rules || true
augenrules --load 2>/dev/null || service auditd restart || true

# ---------------------------------------------------------------------
# 5. Optional: CloudWatch agent, to ship OS logs off the box
# ---------------------------------------------------------------------
if [ "${enable_cloudwatch_agent}" = "true" ]; then
  echo "Installing CloudWatch agent..."
  if command -v dnf >/dev/null 2>&1 || command -v yum >/dev/null 2>&1; then
    $PKG_INSTALL amazon-cloudwatch-agent || true
  elif command -v apt-get >/dev/null 2>&1; then
    curl -s https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb -o /tmp/cwagent.deb \
      && dpkg -i /tmp/cwagent.deb || true
  fi
  # Minimal config: ship auth logs and the audit log this script enabled
  # above. Extend this config as needed for the specific tooling in use.
  cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<'CWCONFIG'
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          { "file_path": "/var/log/audit/audit.log", "log_group_name": "${project_name}-pentest-host-logs", "log_stream_name": "{instance_id}/audit" },
          { "file_path": "/var/log/secure",           "log_group_name": "${project_name}-pentest-host-logs", "log_stream_name": "{instance_id}/secure" }
        ]
      }
    }
  }
}
CWCONFIG
  /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
    -a fetch-config -m ec2 -s \
    -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json || true
fi

echo "=== Pentest environment bootstrap complete: $(date -u) ==="