# Unique suffix so bucket name is globally unique
resource "random_id" "suffix" {
  byte_length = 4
}

# S3 bucket (reports)
resource "aws_s3_bucket" "reports" {
  bucket = "${var.project_name}-reports-${random_id.suffix.hex}"
}

# Block all public access
resource "aws_s3_bucket_public_access_block" "reports" {
  bucket                  = aws_s3_bucket.reports.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Versioning
resource "aws_s3_bucket_versioning" "reports" {
  bucket = aws_s3_bucket.reports.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Default encryption (SSE-S3)
resource "aws_s3_bucket_server_side_encryption_configuration" "reports" {
  bucket = aws_s3_bucket.reports.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Optional: bucket policy that denies unencrypted puts (defense-in-depth)
data "aws_iam_policy_document" "deny_unencrypted_put" {
  statement {
    sid    = "DenyUnEncryptedObjectUploads"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:PutObject"]

    resources = ["${aws_s3_bucket.reports.arn}/*"]

    condition {
      test     = "StringNotEquals"
      variable = "s3:x-amz-server-side-encryption"
      values   = ["AES256"]
    }
  }
}

resource "aws_s3_bucket_policy" "reports" {
  bucket = aws_s3_bucket.reports.id
  policy = data.aws_iam_policy_document.deny_unencrypted_put.json
}

# IAM policy for Jenkins uploads (least privilege to this bucket/prefix)
data "aws_iam_policy_document" "jenkins_reports" {
  statement {
    sid    = "AllowListBucket"
    effect = "Allow"

    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation"
    ]

    resources = [aws_s3_bucket.reports.arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = [var.reports_prefix, "${var.reports_prefix}*"]
    }
  }

  statement {
    sid    = "AllowPutGetObjectsInPrefix"
    effect = "Allow"

    actions = [
      "s3:PutObject",
      "s3:GetObject"
    ]

    resources = [
      "${aws_s3_bucket.reports.arn}/${var.reports_prefix}*"
    ]
  }
}

resource "aws_iam_policy" "jenkins_reports" {
  name        = "${var.project_name}-jenkins-reports-${random_id.suffix.hex}"
  description = "Least-privilege policy for Jenkins to upload/download report artifacts"
  policy      = data.aws_iam_policy_document.jenkins_reports.json
}
