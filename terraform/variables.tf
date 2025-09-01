variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "eu-central-1"
}

variable "project_name" {
  description = "Project name prefix for resource naming"
  type        = string
  default     = "nice-actimize"
}

variable "reports_prefix" {
  description = "S3 prefix/folder where Jenkins will upload reports"
  type        = string
  default     = "reports/"
}
