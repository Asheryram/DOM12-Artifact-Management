output "vpc_id" {
  value = data.aws_vpc.default.id
}

output "public_subnet_ids" {
  value = [data.aws_subnet.public_a.id, data.aws_subnet.public_b.id]
}

# Default VPC has no private subnets; reuse public subnets — SGs enforce isolation
output "private_subnet_ids" {
  value = [data.aws_subnet.public_a.id, data.aws_subnet.public_b.id]
}

output "rds_sg_id" {
  value = aws_security_group.rds.id
}

output "ecs_sg_id" {
  value = aws_security_group.ecs.id
}

output "alb_sg_id" {
  value = aws_security_group.alb.id
}
