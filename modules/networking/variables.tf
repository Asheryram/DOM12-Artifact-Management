variable "project_name" {
  type        = string
  description = "Project name prefix"
}

variable "environment" {
  type        = string
  description = "Environment label"
}

variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region — used to construct AZ names without requiring ec2:DescribeAvailabilityZones"
}
