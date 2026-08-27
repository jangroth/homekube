# Spec 008 — S3 Backup Target via Terraform

**Status:** Draft
**Closes:** issue #20 (`homekube`)
**Unblocks:** issue #21 (Velero + Longhorn backup target), issue #19 (Longhorn scheduled backups)
**Related decisions:** [Decision 058](../../DECISIONS.md) — Terraform adopted as the standard tool for AWS/cloud-account-level infrastructure (wider policy, logged ahead of implementation). A second, bucket-specific DECISIONS.md entry (storage class choice) still gets added on completion per §5 Step 5.

---

## 1. Problem

No backup target exists for the cluster (confirmed live 2026-07-12 — `backup-target` setting empty, no Velero installed). Issue #20 scoped this as a manual AWS console task: create a bucket, an IAM user, and sealed credentials. That's a one-off, undocumented, hard-to-reproduce action — it conflicts with this project's "source reflects runtime" principle (`CLAUDE.md`), which expects infra to be rebuildable from committed source, not console clicks.

## 2. Decision

**Provision the bucket and IAM user with Terraform**, committed to `homekube-main/terraform/`, applied by hand (not automated — see §5 Step 3). Considered and rejected:

- **Crossplane**: would run an AWS-provider controller in-cluster indefinitely for what is a single, rarely-changed resource, and needs its own AWS credentials sealed into the cluster — recreating the exact secret-bootstrapping problem this spec exists to solve. Wrong weight class for one bucket + one IAM policy.
- **Manual console (as originally scoped in #20)**: not reproducible, not versioned, violates "source reflects runtime."

**Storage class: S3 Standard, not Standard-IA.** Backups are daily with 7-day retention (issue #19) — every object is deleted within a week of being written. Standard-IA and Glacier both impose a **minimum storage duration charge** (30 days for Standard-IA, 90 for Glacier) — an object deleted at day 7 is still billed as if stored for the full minimum. At this retention window, IA's lower nominal per-GB rate ($0.0125 vs $0.023/GB-month) is more than offset by paying for storage the object never uses, plus IA's per-GB retrieval fee and higher request costs, which Longhorn/Velero incur on every backup and restore. Standard has no minimum duration and no retrieval fee — it is both simpler and cheaper for this access pattern. (Intelligent-Tiering was also considered: with a 7-day object lifetime, objects never reach its 30-day auto-tiering threshold, so it would just add a small monitoring fee for no benefit.)

At realistic homelab PVC volumes (tens of GB), the absolute cost is low regardless of class — e.g. 50 GB on Standard ≈ $1.15/month — so this decision is about not overpaying via the minimum-duration trap, not about a materially large saving.

**Lifecycle safety net**: add a bucket lifecycle rule expiring objects after 30 days regardless of prefix. Longhorn/Velero retention policies are the primary cleanup mechanism (issues #19/#21 scope); this is a backstop in case a retention policy misconfiguration leaves orphaned objects accumulating cost unnoticed.

**One bucket, one IAM user, prefix-separated**, not two buckets/users — `s3://homekube-backups/longhorn/…` and `s3://homekube-backups/velero/…`. Simpler blast radius for a single-operator homelab; the IAM policy is scoped to the bucket ARN regardless.

**Bucket namespace: account regional, not global.** S3 bucket names are still unique per _partition_ by default (the `aws` commercial partition, not literally global — a minor correction to earlier framing), which is why they've historically felt globally contested. AWS added an opt-in **account regional namespace** in March 2026 ([announcement](https://aws.amazon.com/about-aws/whats-new/2026/03/amazon-s3-account-regional-namespaces), [docs](https://docs.aws.amazon.com/AmazonS3/latest/userguide/gpbucketnamespaces.html)): buckets named `<prefix>-<account-id>-<region>-an` are scoped to your account, sidestepping cross-customer name collisions entirely. Terraform AWS provider ≥6.37.0 supports this via `bucket_namespace = "account-regional"` on `aws_s3_bucket`. This is new enough (this year) to have a few open provider bug reports on edge cases — **verify provider version and behavior at execution time** (Step 0/1 below), same treatment spec 006 gave Cilium's CRD apiVersion drift. Fall back to a classic global-namespace bucket name with a manual uniqueness check if the account-regional path misbehaves.

## 3. Current state (verified 2026-07-12/08-24, re-verify before executing)

| Thing                          | Where                                                                                | Current value                                                                                  |
| ------------------------------ | ------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------- |
| Longhorn backup target         | `kubectl -n longhorn-system get settings.longhorn.io backup-target`                  | empty                                                                                          |
| Velero                         | cluster-wide                                                                         | not installed                                                                                  |
| AWS resources for backups      | —                                                                                    | none exist                                                                                     |
| `.gitignore` (`homekube-main`) | already has `**/.terraform/*`, `**/terraform.tfstate`, `**/terraform.tfstate.backup` | pre-existing, anticipates this work                                                            |
| Terraform in repo              | —                                                                                    | none yet                                                                                       |
| Terraform installed (darth)    | `terraform version`                                                                  | v1.15.8 (latest 1.15.9, not blocking)                                                          |
| AWS CLI installed (darth)      | `aws --version`                                                                      | aws-cli/2.36.29                                                                                |
| AWS credentials (darth)        | `aws sts get-caller-identity`                                                        | none configured — see §5 Step 0                                                                |
| AWS Identity Center            | AWS Console → IAM Identity Center                                                    | enabled 2026-08-24 — instance `ssoins-8259c21f3843a304`, identity store `d-97679fe996`; permission sets not yet provisioned |
| Identity Center user (Jan)     | `aws identitystore list-users --identity-store-id d-97679fe996 --profile jan`        | exists — `jansso`, UserId `192e4408-f0c1-708a-6c47-f957a0335368` (created 2026-08-27) → this is `var.jan_identity_store_user_id` for §4a |
| AWS admin auth (Jan)           | —                                                                                    | IAM user with static access keys — not to be used for ongoing Terraform applies, see §5 Step 0 |

`aws_s3_bucket`'s `bucket_namespace = "account-regional"` verified this session against the AWS provider changelog and AWS's own S3 docs (not just the announcement blog): shipped in provider v6.37.0 (2026-03-18); the `bucket` argument must carry the full `<prefix>-<account-id>-<region>-an` suffix yourself (not auto-appended) when using the CreateBucket API path, which is what §4's `main.tf` already does. `ap-southeast-2` confirmed not excluded (only Middle East Bahrain/UAE are). The one open provider bug ([#47073](https://github.com/hashicorp/terraform-provider-aws/issues/47073)) only affects `bucket_prefix` usage, which this spec doesn't use — no `main.tf` changes needed from the original draft.

## 4. Target state

**Two Terraform-managed pieces**, not one. Jan asked for a dedicated project identity rather than running ongoing applies with the general admin IAM user (2026-08-24) — decision 058 already commits this project to Terraform for AWS resources, this extends that to _how_ Terraform authenticates. Something still has to create that dedicated identity, and creating an identity is itself a privileged action — that one step is the irreducible exception, run once with Jan's admin credentials, same "human-authorization" framing the original §5 Step 3 already used for applies in general. Everything after that, including every future backup-target apply, uses the scoped identity instead.

### 4a. `homekube-main/terraform/bootstrap-identity/`

```
homekube-main/terraform/bootstrap-identity/
├── main.tf
├── variables.tf
├── outputs.tf
└── README.md
```

Creates two IAM Identity Center **permission sets** — `homekube-terraform` (least-privilege, scoped to `homekube-*`-named resources, for applies) and `homekube-readonly` (AWS-managed `ReadOnlyAccess`, safe for inspection/planning) — plus two IAM roles Claude assumes for attribution (see below). Depends on `aws_ssoadmin` data sources for the Identity Center instance, which only exist once Jan has enabled Identity Center for the account (§5 Step 0a, manual, console-only — cannot be automated, same category as this project's NVMe-boot physical checkpoint).

```hcl
data "aws_ssoadmin_instances" "this" {}

locals {
  # Shared with the homekube-agent-terraform IAM role below, so an attributed
  # Claude session carries exactly the same scope as the permission set it
  # layers onto — never more.
  terraform_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:CreateBucket", "s3:DeleteBucket", "s3:GetBucketLocation",
                    "s3:PutBucketPublicAccessBlock", "s3:GetBucketPublicAccessBlock",
                    "s3:PutLifecycleConfiguration", "s3:GetLifecycleConfiguration",
                    "s3:ListBucket"]
        Resource = ["arn:aws:s3:::homekube-*"]
      },
      {
        Effect   = "Allow"
        Action   = ["iam:CreateUser", "iam:DeleteUser", "iam:GetUser", "iam:TagUser",
                    "iam:PutUserPolicy", "iam:DeleteUserPolicy", "iam:GetUserPolicy",
                    "iam:CreateAccessKey", "iam:DeleteAccessKey", "iam:ListAccessKeys"]
        Resource = ["arn:aws:iam::*:user/homekube-*"]
      },
      { Effect = "Allow", Action = ["sts:GetCallerIdentity"], Resource = ["*"] }
    ]
  })
}

# --- homekube-terraform: least-privilege, for actual applies ---
resource "aws_ssoadmin_permission_set" "terraform" {
  name             = "homekube-terraform"
  instance_arn     = tolist(data.aws_ssoadmin_instances.this.arns)[0]
  session_duration = "PT2H"
}

# Scoped to exactly what backup-target's main.tf needs today. Widen deliberately
# as new Terraform-managed AWS resources are added (decision 058) — never broaden
# to a general admin/power-user policy for convenience.
resource "aws_ssoadmin_permission_set_inline_policy" "terraform" {
  instance_arn       = tolist(data.aws_ssoadmin_instances.this.arns)[0]
  permission_set_arn = aws_ssoadmin_permission_set.terraform.arn
  inline_policy      = local.terraform_policy
}

resource "aws_ssoadmin_account_assignment" "terraform" {
  instance_arn       = tolist(data.aws_ssoadmin_instances.this.arns)[0]
  permission_set_arn = aws_ssoadmin_permission_set.terraform.arn
  principal_id       = var.jan_identity_store_user_id
  principal_type     = "USER"
  target_id          = var.aws_account_id
  target_type        = "AWS_ACCOUNT"
}

# --- homekube-readonly: broad AWS-managed read-only, safe for inspection ---
resource "aws_ssoadmin_permission_set" "readonly" {
  name             = "homekube-readonly"
  instance_arn     = tolist(data.aws_ssoadmin_instances.this.arns)[0]
  session_duration = "PT2H"
}

resource "aws_ssoadmin_managed_policy_attachment" "readonly" {
  instance_arn       = tolist(data.aws_ssoadmin_instances.this.arns)[0]
  permission_set_arn = aws_ssoadmin_permission_set.readonly.arn
  managed_policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_ssoadmin_account_assignment" "readonly" {
  instance_arn       = tolist(data.aws_ssoadmin_instances.this.arns)[0]
  permission_set_arn = aws_ssoadmin_permission_set.readonly.arn
  principal_id       = var.jan_identity_store_user_id
  principal_type     = "USER"
  target_id          = var.aws_account_id
  target_type        = "AWS_ACCOUNT"
}

# --- Attribution roles ---
# Claude never gets a standing credential. It assumes one of these on top of
# whichever SSO permission set Jan is logged into, purely so CloudTrail shows
# a distinct actor (assumed-role/homekube-agent-*/claude-session) instead of
# being indistinguishable from Jan's own SSO session. Each role's own policy
# matches its corresponding permission set exactly — assuming it never grants
# anything beyond what Jan already had active.
#
# Trust uses an ArnLike condition on aws:PrincipalArn rather than a direct
# role-ARN reference: the IAM role Identity Center provisions per permission
# set (AWSReservedSSO_<name>_<hash>) doesn't exist, and its hash suffix isn't
# known, until after this same apply creates the account assignment. VERIFY
# the actual provisioned role path at execution time
# (`aws iam list-roles --path-prefix /aws-reserved/sso.amazonaws.com/`) and
# tighten the wildcard if it's looser than necessary — same "verify at
# execution time" treatment as the bucket_namespace provider check in §2/§3.

resource "aws_iam_role" "agent_terraform" {
  name = "homekube-agent-terraform"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::${var.aws_account_id}:root" }
      Action    = "sts:AssumeRole"
      Condition = {
        ArnLike = {
          "aws:PrincipalArn" = "arn:aws:iam::${var.aws_account_id}:role/aws-reserved/sso.amazonaws.com/*/AWSReservedSSO_homekube-terraform_*"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "agent_terraform" {
  name   = "homekube-agent-terraform"
  role   = aws_iam_role.agent_terraform.id
  policy = local.terraform_policy
}

resource "aws_iam_role" "agent_readonly" {
  name = "homekube-agent-readonly"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::${var.aws_account_id}:root" }
      Action    = "sts:AssumeRole"
      Condition = {
        ArnLike = {
          "aws:PrincipalArn" = "arn:aws:iam::${var.aws_account_id}:role/aws-reserved/sso.amazonaws.com/*/AWSReservedSSO_homekube-readonly_*"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "agent_readonly" {
  role       = aws_iam_role.agent_readonly.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}
```

This action list is a starting scope, not verified against a live `terraform plan` yet — expect to tighten or extend it once `backup-target` actually runs against it (Step 0b below calls this out explicitly). Applied once with Jan's admin IAM user credentials.

After this applies, `aws sso login --profile homekube-terraform` (or `--profile homekube-readonly`) produces Jan's own temporary credentials, same as before. When Claude needs to act, it layers one more hop: `aws sts assume-role --role-arn arn:aws:iam::<account_id>:role/homekube-agent-terraform --role-session-name claude-session --profile homekube-terraform`. The resulting session is what Claude actually uses — CloudTrail shows `assumed-role/homekube-agent-terraform/claude-session`, distinct from Jan's own `assumed-role/AWSReservedSSO_homekube-terraform_.../jan...` sessions. No standing credential exists for Claude at any point; the chain always originates from Jan's own SSO login.

### 4b. `homekube-main/terraform/backup-target/`

```
homekube-main/terraform/backup-target/
├── main.tf
├── variables.tf
├── outputs.tf
└── README.md          # apply/destroy instructions, not project docs (this dir is operator-facing)
```

`main.tf`:

```hcl
terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.37" }  # >= 6.37.0 for bucket_namespace
  }
  # Local state — single operator, no remote backend. A remote S3 backend would be
  # circular (this bucket doesn't exist yet), and a second bucket just for state
  # is overkill for one operator. State file stays local, gitignored.
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile  # SSO profile from 4a's permission set — run `aws sso login --profile <this>` first
}

data "aws_caller_identity" "current" {}

# Account regional namespace (AWS, March 2026) — avoids cross-account name
# collisions entirely; scoped to this account+region instead of the shared
# partition-wide namespace. Requires AWS provider >= 6.37.0 — VERIFY at
# execution time (see §5 Step 0), fall back to a plain global-namespace
# `bucket = var.bucket_name` + manual uniqueness check if this misbehaves.
resource "aws_s3_bucket" "backups" {
  bucket           = "${var.bucket_name}-${data.aws_caller_identity.current.account_id}-${var.aws_region}-an"
  bucket_namespace = "account-regional"
}

resource "aws_s3_bucket_public_access_block" "backups" {
  bucket                  = aws_s3_bucket.backups.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Backstop only — Longhorn (issue #19) and Velero (issue #21) own actual retention.
resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id
  rule {
    id     = "safety-net-expiry"
    status = "Enabled"
    filter {}
    expiration { days = 30 }
    # expiration doesn't cover abandoned multipart parts — invisible in listings,
    # accumulate cost silently.
    abort_incomplete_multipart_upload { days_after_initiation = 7 }
  }
}

resource "aws_iam_user" "backup" {
  name = "homekube-backup"
}

resource "aws_iam_user_policy" "backup" {
  name = "homekube-backup-s3"
  user = aws_iam_user.backup.name
  # Object actions include multipart-upload perms — Velero's AWS plugin requires
  # them, and Longhorn multipart-uploads large backups.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetBucketLocation"]
        Resource = [aws_s3_bucket.backups.arn]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject", "s3:GetObject", "s3:DeleteObject",
          "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts"
        ]
        Resource = ["${aws_s3_bucket.backups.arn}/*"]
      }
    ]
  })
}

resource "aws_iam_access_key" "backup" {
  user = aws_iam_user.backup.name
}
```

`variables.tf`: `aws_region` (default `ap-southeast-2` — Jan's preference), `bucket_name` (default `homekube-backups`; the account-regional namespace suffix in `main.tf` makes this collision-free, so no manual availability check needed), `aws_profile` (default `homekube-terraform` — the SSO profile created by 4a, not the admin profile).

`outputs.tf`: `bucket_name`, `bucket_region`, `access_key_id`, `secret_access_key` (`sensitive = true`).

Note: the local `terraform.tfstate` stores the secret access key in plaintext — the state file _is_ a credential store. Gitignore covers the commit risk; handle the file itself like the Step 4 output (stays on darth, never leaves the machine).

## 5. Execution plan

Per `feedback_ansible_execution` / `feedback_implementation_pace`: show each command, wait for confirmation, one chunk at a time.

**Step 0a — Enable AWS IAM Identity Center.** ✅ **Done 2026-08-28.** Jan, manual, console-only, one-time. Identity Center is active (§3) and Jan's Identity Center user (`jansso`) exists — both prerequisites for §4a's account assignments are satisfied. Next up is Step 0b.

**Step 0b — Write & apply `bootstrap-identity` (§4a).** Write the four files, `terraform init`/`plan`/`apply` using Jan's _admin_ IAM user credentials — the one deliberately-scoped exception to "don't use admin creds," since creating the scoped identity is itself a privileged action nothing less-privileged can perform. Show plan output before applying: expect exactly 10 resources — 2 permission sets, 1 inline policy + 1 managed-policy attachment, 2 account assignments, 2 attribution IAM roles, and their 1 inline policy + 1 managed-policy attachment. Confirm `aws sso login --profile homekube-terraform` and `--profile homekube-readonly` both work afterward, and that `aws sts assume-role --role-arn <homekube-agent-terraform ARN> --role-session-name claude-session --profile homekube-terraform` succeeds, before moving on.

**Step 0c — Pre-flight for `backup-target`.**

- Confirm installed AWS provider version supports `bucket_namespace` (`terraform providers` / provider changelog — need ≥6.37.0; verified this session, see §3).
- Confirm `ap-southeast-2` (Sydney) has no restriction on account regional namespaces (verified this session, see §3).
- Confirm `homekube-terraform` SSO profile is logged in (`aws sso login --profile homekube-terraform`) and `aws sts get-caller-identity --profile homekube-terraform` resolves to the permission set's assumed-role identity, not the admin user.

**Step 1 — Write Terraform files.** Create the four files in §4b.

**Step 2 — `terraform init` / `terraform plan`.** Show plan output before applying. Review: exactly 1 bucket, 1 public-access-block, 1 lifecycle config, 1 IAM user, 1 IAM policy, 1 access key — nothing else. If `plan` fails on an `AccessDenied` for an action `bootstrap-identity`'s policy didn't anticipate, fix it there (§4a) and re-apply `bootstrap-identity` first — don't work around it by falling back to the admin profile.

**Step 3 — `terraform apply`.** Run by Jan (or by Claude with Jan watching) using the `homekube-terraform` SSO profile — this is the human-authorization step #20 always required; Terraform makes it reproducible, not unattended, and the scoped identity means an apply here can't touch anything outside `homekube-*`-named resources even in error.

**Step 4 — Capture outputs.** `terraform output -json` for `bucket_name`/`bucket_region`, `terraform output -raw secret_access_key` separately (don't let it land in shell history — pipe to a file outside the repo, or read directly for sealing). This output is the handoff point to issue #21 (Velero install + Longhorn backup-target secret via `kubeseal`) — sealing/consuming the credentials is out of scope here.

**Step 5 — Close out.** Update `DECISIONS.md` — the Terraform-vs-Crossplane + storage-class rationale already drafted in §2, condensed to decision-log format, plus a short addendum to decision 058 recording the final `bootstrap-identity` permission-set scope (as actually applied, not just the starting draft in §4a) and the attribution-role design (Claude assumes a role, never holds a standing credential). `CHANGELOG.md` entry, close issue #20, flip this spec's Status to Done.

## 6. Validation / acceptance criteria

- [ ] `homekube-terraform` SSO permission set exists, is assigned to Jan, and `backup-target`'s apply in Step 3 ran under it (not the admin profile) — check `aws sts get-caller-identity --profile homekube-terraform` before/after.
- [ ] `terraform plan` after apply shows no diff (state matches reality).
- [ ] `aws s3api get-bucket-lifecycle-configuration --bucket <name>` shows the 30-day expiry rule.
- [ ] `aws s3api get-public-access-block --bucket <name>` shows all four block flags `true`.
- [ ] IAM user `homekube-backup` can `PutObject`/`GetObject`/`DeleteObject` + multipart actions on objects, `ListBucket`/`GetBucketLocation` on the bucket, and nothing else (spot-check with `aws s3 cp` using the generated access key, or `aws iam simulate-principal-policy`).
- [ ] `aws sts assume-role --role-arn <homekube-agent-terraform ARN> --role-session-name claude-session --profile homekube-terraform` succeeds, and the resulting `GetCallerIdentity` ARN shows `assumed-role/homekube-agent-terraform/claude-session` — confirms attribution works and the role is scoped identically to the permission set it layers onto.
- [ ] Outputs captured and available for issue #21 — not committed anywhere in git.
- [ ] `homekube-main/.gitignore` already covers `.terraform/` and `*.tfstate*` — confirm no state or secret material got staged (`git status` before any commit in this directory).

## 7. Rollback

`terraform destroy` in `homekube-main/terraform/backup-target/` — removes bucket, IAM user, policy, access key. Safe as long as issue #21/#19 haven't yet written real backup data to the bucket; if they have, this is destructive (irreversible data loss) and needs explicit confirmation before running, per this project's destructive-action policy.

## 8. Notes / open questions for Jan

- **Region**: `ap-southeast-2` (Sydney), per Jan.
- **Bucket name**: `homekube-backups` + account regional namespace suffix — collision-free, no availability check needed (see §2/§4b).
- **Identity**: Jan wants a dedicated project identity, not ongoing use of the admin IAM user (2026-08-24) — resolved as an SSO permission set (§4a), not a static-key IAM user, since Jan's admin auth already uses static keys and the point is to not add another long-lived secret. Required Jan to enable IAM Identity Center first (§5 Step 0a) — **done 2026-08-28**; ready for Step 0b (write & apply `bootstrap-identity`).
- **`bootstrap-identity`'s policy is a starting scope**, deliberately not verified against a live `terraform plan` yet (§4a) — expect at least one iteration once Step 0b/Step 2 actually run.
- **Attribution identity for Claude** (2026-08-28): Claude never gets a standing AWS credential — for genuinely autonomous/unattended access, that would mean a static-key IAM user again (reintroducing the exact long-lived-secret problem this spec exists to remove) or IAM Roles Anywhere with its own cert-management overhead, and it would break the "Claude proposes, human approves" trust model this project runs on. Attribution-only was chosen instead: Claude layers an `sts:AssumeRole` hop onto whichever SSO permission set Jan already has active, via dedicated `homekube-agent-terraform`/`homekube-agent-readonly` IAM roles (§4a), so CloudTrail can tell Claude-attributed actions apart from Jan's own SSO sessions without expanding what either can do. The trust policies use an `ArnLike` wildcard on `aws:PrincipalArn` rather than a hardcoded role ARN, since the SSO-provisioned role name isn't known until after the same apply — verify the actual provisioned role path at execution time (Step 0b).
- **Out of scope here**: sealing the credentials into the cluster, installing Velero, configuring Longhorn's `backup-target` setting, and the recurring-job schedule — all issue #21/#19 work, unblocked but not done by this spec.
