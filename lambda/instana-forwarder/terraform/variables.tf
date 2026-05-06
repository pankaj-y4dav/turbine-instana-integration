variable "instana_base_url" {
  description = "Instana base URL e.g. https://test-hcp.instana.io"
  type        = string
}

variable "instana_api_key" {
  description = "Instana API token"
  type        = string
  sensitive   = true
}

variable "log_service_name" {
  description = "Service name tag attached to forwarded logs"
  type        = string
  default     = "cloudwatch"
}

variable "cloudwatch_log_group_name" {
  description = "CloudWatch Log Group to subscribe to"
  type        = string
}

variable "filter_pattern" {
  description = "CloudWatch subscription filter pattern"
  type        = string
  default     = ""
}

variable "backup_bucket_name" {
  description = "S3 bucket name for Firehose backup and failed records"
  type        = string
}

variable "log_retention_days" {
  description = "Retention period in days for the CloudWatch Log Group"
  type        = number
  default     = 30
}

variable "backup_retention_days" {
  description = "Days to retain backup logs in S3"
  type        = number
  default     = 30
}
