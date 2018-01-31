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

variable "public_subnets" {
  type = "list"
}

variable "private_subnets" {
  type = "list"
}

variable "vpc_cidr_block" {}

variable "enable_nat_gateway" {
  type = "string"
}

variable "single_nat_gateway" {
  type = "string"
}

variable "tidb_count" {}

variable "tikv_count" {}

variable "pd_count" {}

variable "monitor_count" {
  default = 0
}
