locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    DR          = "target"
  }
}

resource "aws_vpc" "dr" {
  cidr_block           = "10.1.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = merge(local.common_tags, { Name = "${var.project_name}-dr-vpc" })
}

resource "aws_subnet" "dr_private_a" {
  vpc_id            = aws_vpc.dr.id
  cidr_block        = "10.1.11.0/24"
  availability_zone = "${var.aws_region}a"
  tags = merge(local.common_tags, { Name = "${var.project_name}-dr-private-a" })
}

resource "aws_subnet" "dr_private_b" {
  vpc_id            = aws_vpc.dr.id
  cidr_block        = "10.1.12.0/24"
  availability_zone = "${var.aws_region}b"
  tags = merge(local.common_tags, { Name = "${var.project_name}-dr-private-b" })
}

resource "aws_security_group" "dr_rds" {
  name        = "${var.project_name}-dr-rds-sg"
  description = "DR RDS security group"
  vpc_id      = aws_vpc.dr.id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["10.1.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.common_tags
}

resource "aws_db_subnet_group" "dr" {
  name       = "${var.project_name}-dr-subnet-group"
  subnet_ids = [aws_subnet.dr_private_a.id, aws_subnet.dr_private_b.id]
  tags       = local.common_tags
}
