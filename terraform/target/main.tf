# ─────────────────────────────────────────────────────────────
# "Crown jewels" bucket — the objective for T1530.
#
# NOT public: deny-s3-public-access (Workloads OU) denies both
# PutBucketPublicAccessBlock and public ACLs. Exposure is instead
# modelled via an over-permissive bucket policy, which is both
# more realistic and the only route the SCP leaves open.
# ─────────────────────────────────────────────────────────────

resource "aws_s3_bucket" "crown_jewels" {
  bucket        = "${local.prefix}-customer-data-${var.sandbox_account_id}"
  force_destroy = true
}

resource "aws_s3_object" "fake_pii" {
  bucket  = aws_s3_bucket.crown_jewels.id
  key     = "exports/customer-export-2026-q2.csv"
  content = <<-EOT
    customer_id,name,email,plan,mrr
    1001,SYNTHETIC TEST DATA,test1@example.invalid,enterprise,4200
    1002,SYNTHETIC TEST DATA,test2@example.invalid,pro,890
    1003,SYNTHETIC TEST DATA,test3@example.invalid,pro,890
  EOT
}

resource "aws_s3_object" "fake_creds" {
  bucket  = aws_s3_bucket.crown_jewels.id
  key     = "config/app.env"
  content = <<-EOT
    # SYNTHETIC — not real credentials
    DB_HOST=internal-db.range.invalid
    DB_PASSWORD=NOT_A_REAL_SECRET_synthetic_lab_value
  EOT
}

# Over-permissive: any principal in this account, no conditions.
resource "aws_s3_bucket_policy" "crown_jewels" {
  bucket = aws_s3_bucket.crown_jewels.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "OverlyPermissiveAccountWideRead"
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::${var.sandbox_account_id}:root" }
      Action    = ["s3:GetObject", "s3:ListBucket"]
      Resource = [
        aws_s3_bucket.crown_jewels.arn,
        "${aws_s3_bucket.crown_jewels.arn}/*"
      ]
    }]
  })
}

# ─────────────────────────────────────────────────────────────
# Over-permissive role with a weak trust policy.
# Models the "one role to rule them all" antipattern.
# ─────────────────────────────────────────────────────────────

resource "aws_iam_role" "over_permissive" {
  name = "${local.prefix}-app-deploy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::${var.sandbox_account_id}:root" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "over_permissive" {
  name = "${local.prefix}-app-deploy-policy"
  role = aws_iam_role.over_permissive.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:*", "iam:PassRole", "iam:Get*", "iam:List*", "ec2:*"]
      Resource = "*"
    }]
  })
}

output "crown_jewels_bucket" {
  value = aws_s3_bucket.crown_jewels.id
}

output "over_permissive_role_arn" {
  value = aws_iam_role.over_permissive.arn
}