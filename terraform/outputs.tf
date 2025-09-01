output "bucket_name" {
  description = "Name of the S3 bucket for reports"
  value       = aws_s3_bucket.reports.bucket
}

output "jenkins_reports_policy_arn" {
  description = "IAM policy ARN to attach to Jenkins principal (user/role)"
  value       = aws_iam_policy.jenkins_reports.arn
}
