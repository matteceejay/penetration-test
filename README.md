# penetration-testmarkdown
# Temporary Pentest Environment — Terraform Project

Self-contained Terraform project for a temporary AWS penetration-testing
environment, built directly from a third-party vendor's requirements list.
It has its own state (see `versions.tf`) so it never gets tangled up with
any other Terraform project in the account, and it's meant to be spun up
before an engagement and fully destroyed after.

This is a **preliminary build**. Several values depend on answers the
vendor hasn't confirmed yet (which distro, which instance type, SSH vs
SSM, source IPs, storage size, and exactly which resources they'll be
scanning). Every one of those lives in `terraform.tfvars` as a clearly
marked placeholder — see Section 3 for exactly how to fill each one in
once confirmed.

---

## 1. What each file does, and how they connect

Terraform reads every `.tf` file in the folder and links resources
together by reference, regardless of which file declares them — file
order doesn't matter to Terraform. Conceptually though, the files build
on each other like this:

variables.tf ──defines the "shape" of every input──┐
│
terraform.tfvars ──supplies the actual values────────►│
│
▼
data.tf ──looks up the approved VPC/subnet + AMI──► ec2.tf
▲
security_group.tf ──creates SG (if SSH)──────────────►│
iam.tf ──creates role + instance profile─────────────►│
storage.tf ──creates KMS key + data volume───────────►│
templates/user_data.sh.tpl ──bootstrap script─────────►│
│
logging.tf ──watches the subnet + (if SSM) sessions───┘
│
▼
outputs.tf ──surfaces IDs/IPs/commands from all of the above


**`versions.tf`**
Pins the Terraform CLI and AWS provider versions, and defines the remote
state backend. This is what makes the project "separate" — its state
lives in its own S3 key, isolated from any other infrastructure you
manage. Also sets `default_tags` on the AWS provider, which is how every
resource in every other file automatically gets tagged with Project /
Owner / Purpose / Expiration without each file having to repeat it.

**`variables.tf`**
Declares every input the project accepts — type, description, and a
default where one is safe. This file defines *what can be configured*; it
holds no actual values. Every other file references these variables as
`var.something`.

**`terraform.tfvars`**
The file you actually edit. Supplies the real values for everything
`variables.tf` declared — this is where all the vendor's answers
(VPC/subnet, instance type, distro, connection method, source IPs,
storage size, IAM scope, tester list) end up. See Section 3 below for how
to update it as answers arrive.

**`data.tf`**
Read-only lookups: confirms the VPC/subnet IDs from `terraform.tfvars`
actually exist, and resolves the correct AMI ID based on `os_family`.
Produces `local.selected_ami_id`, which `ec2.tf` consumes directly — this
is the file that turns "ubuntu-22.04" (a string) into a real AMI ID AWS
can launch.

**`security_group.tf`**
Only creates resources if `connection_method = "ssh"`. Builds the security
group and the inbound rule restricted to `allowed_source_cidrs`.
`ec2.tf` attaches this security group to the instance when it exists, and
skips it entirely when using SSM (since SSM needs no inbound rule at all).

**`iam.tf`**
Builds the least-privilege IAM role and instance profile. The policy
itself is built from `var.iam_policy_statements` — a list of statements,
each with its own `actions` and `resources`, so different AWS services in
scope (S3, EC2, RDS, etc.) each get exactly the access and target ARNs
they need without cross-applying one service's actions to another
service's resources. `ec2.tf` attaches the instance profile this file
creates. If `connection_method = "ssm"`, this file also attaches the
AWS-managed SSM policy so Session Manager can actually reach the box.

**`storage.tf`**
Creates the dedicated KMS key (unless you supplied one) and the encrypted
EBS volume that holds tester tools/output. The volume attachment resource
here references `aws_instance.pentest.id` from `ec2.tf`, and `ec2.tf` in
turn uses `local.kms_key_id_effective` (defined here) to encrypt the root
volume — a two-way dependency that Terraform resolves automatically via
its dependency graph, so you don't need to apply things in a particular
order yourself.

**`ec2.tf`**
The instance itself — the hub all the other files feed into. Pulls the
AMI from `data.tf`, the security group from `security_group.tf`, the
instance profile from `iam.tf`, the KMS key from `storage.tf`, and renders
`templates/user_data.sh.tpl` with values from `terraform.tfvars` to
produce the actual boot script AWS runs on first launch.

**`templates/user_data.sh.tpl`**
Not a `.tf` file — a bash script template. Runs once when the instance
first boots: installs `approved_packages`, creates one Linux user account
per entry in `testers`, mounts the encrypted data volume at `/data` with a
private subdirectory per tester, and turns on command auditing. Terraform
fills in the `${...}` placeholders via the `templatefile()` call in
`ec2.tf`.

**`logging.tf`**
Sets up VPC Flow Logs on `var.subnet_id` (network-level tracing), a
CloudWatch log group for host logs (if `enable_cloudwatch_agent = true`,
matching what the user-data script ships logs to), and — only if
`connection_method = "ssm"` — a Session Manager logging document so every
interactive session is recorded by AWS itself.

**`outputs.tf`**
After `terraform apply`, surfaces the values you'll actually need: the
instance ID, its IP, the SSM connect command or security group ID
depending on connection method, the IAM role ARN, the KMS key ARN, the
data volume ID (for pre-teardown snapshotting), and the flow log group
name.

---

## 2. Setup steps

### Step 1 — Lay out the folder

pentest-environment/
├── README.md
├── versions.tf
├── variables.tf
├── terraform.tfvars
├── data.tf
├── security_group.tf
├── iam.tf
├── storage.tf
├── ec2.tf
├── logging.tf
├── outputs.tf
└── templates/
└── user_data.sh.tpl


### Step 2 — Decide on state storage
Open `versions.tf`. Either replace the `REPLACE_ME` bucket/region in the
`backend "s3"` block with a real bucket you control, or comment out the
entire `backend "s3" { ... }` block to use local state (fine for a
short-lived, single-operator project).

### Step 3 — Fill in what you already know
Open `terraform.tfvars` and fill in the account/tagging fields
(`aws_region`, `project_name`, `owner`, `expiration_date`) — you already
have these regardless of what the vendor confirms.

### Step 4 — Initialize
```bash
terraform init
```

### Step 5 — Plan early, even with placeholders left in
```bash
terraform plan
```
This works fine with `REPLACE_ME` values still in place — use it now to
confirm the code itself is sound, before you have every vendor answer.

### Step 6 — Fill in the rest of `terraform.tfvars` as answers arrive
See Section 3 below for exactly what to change and where.

### Step 7 — Final plan and review before applying
```bash
terraform plan
```
Confirm before applying:
- No security group rule allows `0.0.0.0/0`.
- No `iam_policy_statements` entry still has a placeholder `sid`,
  `actions`, or `resources`.
- `vpc_id` / `subnet_id` match what network/security actually approved.

### Step 8 — Apply
```bash
terraform apply
```
Review the outputs (`instance_id`, `ssm_connect_command` or
`security_group_id`, `iam_role_arn`) — these are what you hand off to the
vendor and reference if scope questions come up mid-engagement.

### Step 9 — Support the engagement
- Share connection details from the outputs.
- Confirm each tester logs in as their own account (`whoami` shows their
  individual username).
- Point testers to `/data/<their username>` for tools/output.
- Monitor the CloudWatch log groups during the engagement if you need to
  trace activity in real time.

### Step 10 — Teardown after testing + evidence collection are complete
1. **Collect evidence first** — copy `/data` contents off the instance or
   snapshot the data volume:
```bash
   aws ec2 create-snapshot --volume-id <data_volume_id output> \
     --description "Pentest evidence snapshot - <project_name>"
```
2. **Remove vendor access** as soon as testing is confirmed done — revoke
   SSH keys or SSM access even if the full `destroy` happens slightly
   later while you finish collecting evidence.
3. **Destroy:**
```bash
   terraform destroy
```
4. Confirm in the AWS console (or `aws ec2 describe-instances`) that the
   instance, volumes, and security group are gone.
5. If a dedicated KMS key was created, it enters a 7-day pending-deletion
   window automatically — don't delete any evidence snapshots encrypted
   with it until you're sure you won't need to decrypt them again.

---

## 3. Updating `terraform.tfvars` once the vendor confirms requirements

This section walks through each open question, what to change, and what
it looks like filled in. Nothing else in the project needs to change —
every one of these is a plain value swap in `terraform.tfvars`.

### "Which Linux distribution should be used?"
Change `os_family` to one of the three supported values:
```hcl
os_family = "ubuntu-22.04"   # was "amazon-linux-2023"
```
Leave `ami_id_override = null` unless the vendor requires a specific
pre-approved/hardened image — in that case, put the AMI ID there instead:
```hcl
ami_id_override = "ami-0123456789abcdef0"
```

### "What EC2 instance type is approved?"
```hcl
instance_type = "t3.large"   # was "REPLACE_ME"
```

### "Which VPC and subnet should host the instance?"
```hcl
vpc_id    = "vpc-0123456789abcdef0"      # was "REPLACE_ME"
subnet_id = "subnet-0123456789abcdef0"   # was "REPLACE_ME"
```

### "Will the vendor connect through SSH or SSM?"
```hcl
connection_method = "ssm"   # or "ssh" — was "REPLACE_ME"
```
- If `"ssm"`: leave `allowed_source_cidrs` and `ssh_public_key` as-is
  (empty) — they're unused in SSM mode.
- If `"ssh"`: continue to the next section.

### "What source IP addresses should be allowed?" (SSH only)
```hcl
allowed_source_cidrs = ["203.0.113.10/32"]   # was []
ssh_public_key        = "ssh-ed25519 AAAA... admin"
```
Use the vendor's exact confirmed IPs, as `/32` (single address) entries
where possible — never a broad range unless the vendor specifically
provides one.

### Tester accounts
Add one object per tester once the vendor provides names/keys:
```hcl
testers = [
  { username = "vendor_jsmith", public_key = "ssh-ed25519 AAAA... jsmith" },
  { username = "vendor_agupta", public_key = "ssh-ed25519 AAAA... agupta" },
]
```
Leave `public_key = ""` per tester if `connection_method = "ssm"` — they
won't need one.

### Approved packages
```hcl
approved_packages = ["nmap", "tcpdump", "python3-pip"]   # was []
```

### "How much storage is required?"
```hcl
root_volume_size_gb = 30    # usually fine as-is
data_volume_size_gb = 250   # was 100 — bump based on expected scan/output volume
```

### "Exactly which AWS services/resources are the testers permitted to access?"
This is the one that maps to `iam_policy_statements` — a list, so add one
entry per distinct service/access-level combination the vendor confirms.
Don't merge unrelated services into one entry (see the note at the bottom
of this section for why).

Before:
```hcl
iam_policy_statements = [
  {
    sid       = "REPLACE_ME_PENDING_VENDOR_SCOPE"
    actions   = ["REPLACE_ME_WITH_APPROVED_ACTIONS"]
    resources = ["REPLACE_ME_WITH_APPROVED_RESOURCE_ARNS"]
  },
]
```

After (example — replace with the vendor's actual confirmed scope):
```hcl
iam_policy_statements = [
  {
    sid       = "S3ReadOnlyScopedBuckets"
    actions   = ["s3:ListBucket", "s3:GetObject"]
    resources = [
      "arn:aws:s3:::approved-test-bucket",
      "arn:aws:s3:::approved-test-bucket/*",
    ]
  },
  {
    sid       = "EC2DescribeOnly"
    actions   = ["ec2:DescribeInstances", "ec2:DescribeSecurityGroups"]
    resources = ["*"]   # describe-type actions usually can't be scoped to a specific ARN
  },
]
```

**Why keep services in separate statements:** if you put `s3:GetObject`
and `ec2:DescribeInstances` in the same statement with both resource ARNs
combined, Terraform builds a policy that grants *every* action in that
statement against *every* resource in it — meaning `s3:GetObject` would
technically apply to the EC2 ARN too. Splitting by service keeps the
policy an accurate reflection of the vendor's actual, narrower scope.

### Quick checklist before your final `terraform plan`
- [ ] No value in `terraform.tfvars` still says `REPLACE_ME`
- [ ] `allowed_source_cidrs` has real IPs (if SSH) — never empty or `0.0.0.0/0`
- [ ] Every `iam_policy_statements` entry has a real `sid`, `actions`, and `resources`
- [ ] `testers` has one entry per confirmed tester
- [ ] `data_volume_size_gb` reflects expected output volume, not just the default

---

## 4. Notes on the two connection methods

- **SSM (recommended where the vendor's tooling allows it):** no inbound
  port, no security group needed, every session logged by AWS
  automatically via `logging.tf`'s session preferences document. Testers
  connect via `aws ssm start-session` and then `sudo su - <their
  username>` to work from their own account and `/data` subdirectory.
- **SSH:** requires `allowed_source_cidrs` to be the vendor's real,
  confirmed source IPs, and each tester's individual public key in
  `testers`.