variable "aws_access_key" {
  type        = "string"
  description = "Your AWS access key id"
}

variable "aws_secret_key" {
  type        = "string"
  description = "Your AWS secret key"
}

variable "aws_region" {
  type        = "string"
  description = "The AWS region you want to create resources"
  default     = "us-east-1"
}

variable "tidb_count" {}

variable "tikv_count" {}

variable "pd_count" {}

variable "monitor_count" {
  default = 0
}
