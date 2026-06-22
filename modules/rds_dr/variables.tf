variable "project_name" { type = string }
variable "environment" { type = string }
variable "db_name" { type = string }
variable "aws_region" {
  type    = string
  default = "us-west-2"
  description = "DR region — used to construct AZ names without requiring ec2:DescribeAvailabilityZones"
}
