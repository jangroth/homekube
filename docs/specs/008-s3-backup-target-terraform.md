# Spec 008 — S3 Backup Target via Terraform

**Status:** Draft
**Closes:** issue #20 (`homekube`)
**Unblocks:** issue #21 (Velero + Longhorn backup target), issue #19 (Longhorn scheduled backups)
**Related decisions:** none yet — this spec is the design record; a DECISIONS.md entry gets added on completion (Terraform vs Crossplane, storage class choice)

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

## 3. Current state (verified 2026-07-12, re-verify before executing)

| Thing                          | Where                                                                                | Current value                       |
| ------------------------------ | ------------------------------------------------------------------------------------ | ----------------------------------- |
| Longhorn backup target         | `kubectl -n longhorn-system get settings.longhorn.io backup-target`                  | empty                               |
| Velero                         | cluster-wide                                                                         | not installed                       |
| AWS resources for backups      | —                                                                                    | none exist                          |
| `.gitignore` (`homekube-main`) | already has `**/.terraform/*`, `**/terraform.tfstate`, `**/terraform.tfstate.backup` | pre-existing, anticipates this work |
| Terraform in repo              | —                                                                                    | none yet                            |

## 4. Target state

New directory `homekube-main/terraform/backup-target/`:

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
  region = var.aws_region
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

`variables.tf`: `aws_region` (default `ap-southeast-2` — Jan's preference), `bucket_name` (default `homekube-backups`; the account-regional namespace suffix in `main.tf` makes this collision-free, so no manual availability check needed).

`outputs.tf`: `bucket_name`, `bucket_region`, `access_key_id`, `secret_access_key` (`sensitive = true`).

Note: the local `terraform.tfstate` stores the secret access key in plaintext — the state file *is* a credential store. Gitignore covers the commit risk; handle the file itself like the Step 4 output (stays on darth, never leaves the machine).

## 5. Execution plan

Per `feedback_ansible_execution` / `feedback_implementation_pace`: show each command, wait for confirmation, one chunk at a time.

**Step 0 — Pre-flight.**

- Confirm AWS account exists and Jan has admin/IAM-creation credentials available locally (`aws configure` or env vars). This is the one step that cannot be automated — Terraform needs _some_ AWS identity to bootstrap from.
- Confirm installed AWS provider version supports `bucket_namespace` (`terraform providers` / provider changelog — need ≥6.37.0). If not available or `apply` errors on the account-regional path, fall back to a global-namespace `bucket = var.bucket_name` and check availability manually before retrying.
- Confirm `ap-southeast-2` (Sydney) has no restriction on account regional namespaces (per docs, only excluded in the two Middle East regions as of the March 2026 announcement — should be fine, re-verify at execution time).

**Step 1 — Write Terraform files.** Create the four files in §4.

**Step 2 — `terraform init` / `terraform plan`.** Show plan output before applying. Review: exactly 1 bucket, 1 public-access-block, 1 lifecycle config, 1 IAM user, 1 IAM policy, 1 access key — nothing else.

**Step 3 — `terraform apply`.** Run by Jan (or by Claude with Jan watching) using Jan's own AWS credentials — this is the human-authorization step #20 always required; Terraform makes it reproducible, not unattended.

**Step 4 — Capture outputs.** `terraform output -json` for `bucket_name`/`bucket_region`, `terraform output -raw secret_access_key` separately (don't let it land in shell history — pipe to a file outside the repo, or read directly for sealing). This output is the handoff point to issue #21 (Velero install + Longhorn backup-target secret via `kubeseal`) — sealing/consuming the credentials is out of scope here.

**Step 5 — Close out.** Update `DECISIONS.md` (Terraform-vs-Crossplane + storage-class rationale — already drafted in §2, condense to decision-log format), `CHANGELOG.md` entry, close issue #20, flip this spec's Status to Done.

## 6. Validation / acceptance criteria

- [ ] `terraform plan` after apply shows no diff (state matches reality).
- [ ] `aws s3api get-bucket-lifecycle-configuration --bucket <name>` shows the 30-day expiry rule.
- [ ] `aws s3api get-public-access-block --bucket <name>` shows all four block flags `true`.
- [ ] IAM user `homekube-backup` can `PutObject`/`GetObject`/`DeleteObject` + multipart actions on objects, `ListBucket`/`GetBucketLocation` on the bucket, and nothing else (spot-check with `aws s3 cp` using the generated access key, or `aws iam simulate-principal-policy`).
- [ ] Outputs captured and available for issue #21 — not committed anywhere in git.
- [ ] `homekube-main/.gitignore` already covers `.terraform/` and `*.tfstate*` — confirm no state or secret material got staged (`git status` before any commit in this directory).

## 7. Rollback

`terraform destroy` in `homekube-main/terraform/backup-target/` — removes bucket, IAM user, policy, access key. Safe as long as issue #21/#19 haven't yet written real backup data to the bucket; if they have, this is destructive (irreversible data loss) and needs explicit confirmation before running, per this project's destructive-action policy.

## 8. Notes / open questions for Jan

- **Region**: `ap-southeast-2` (Sydney), per Jan.
- **Bucket name**: `homekube-backups` + account regional namespace suffix — collision-free, no availability check needed (see §2/§4).
- **Out of scope here**: sealing the credentials into the cluster, installing Velero, configuring Longhorn's `backup-target` setting, and the recurring-job schedule — all issue #21/#19 work, unblocked but not done by this spec.
