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

variable "vpc_cidr_block" {
  type        = "string"
  description = "Your AWS vpc CIDR block for tidb cluster"
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "AWS Availability Zones Used"
  type        = "list"
}

variable "public_subnets" {
  description = "Public Subnets CIDR"
  default     = []
}

variable "private_subnets" {
  description = "Private Subnets CIDR"
  default     = []
}

variable "enable_nat_gateway" {
  description = "Should be true if you want to provision NAT Gateways for each of your private networks"
  default     = false
}

variable "single_nat_gateway" {
  description = "Should be true if you want to provision a single shared NAT Gateway across all of your private networks"
  default     = false
}

variable "tidb_count" {}

variable "tikv_count" {}

variable "pd_count" {}

variable "monitor_count" {
  default = 0
}
