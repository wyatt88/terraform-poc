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
  description = "Should be true if you want to provision NAT Gateways for each of your private networks"
}

variable "single_nat_gateway" {
  description = "Should be true if you want to provision a single shared NAT Gateway across all of your private networks"
}

variable "tidb_instance_type_number" {
  description = "1 t2.micro \n 2 c4.large"
  type        = "string"
}

variable "tidb_instance_type_map" {
  type = "map"

  default = {
    "1" = "t2.micro"
    "2" = "c4.large"
  }
}

variable "tikv_instance_type_number" {
  description = "1 t2.micro \n 2 c4.large"
  type        = "string"
}

variable "tikv_instance_type_map" {
  type = "map"

  default = {
    "1" = "t2.micro"
    "2" = "c4.large"
  }
}

variable "pd_instance_type_number" {
  description = " 1 t2.micro \n 2 c4.large"
  type        = "string"
}

variable "pd_instance_type_map" {
  type = "map"

  default = {
    "1" = "t2.micro"
    "2" = "c4.large"
  }
}

variable "tidb_count" {}

variable "tikv_count" {}

variable "pd_count" {}

variable "monitor_count" {}
