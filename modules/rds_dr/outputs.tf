output "dr_subnet_group_name" { value = aws_db_subnet_group.dr.name }
output "dr_vpc_id" { value = aws_vpc.dr.id }
output "dr_rds_sg_id" { value = aws_security_group.dr_rds.id }
output "dr_private_subnet_ids" { value = [aws_subnet.dr_private_a.id, aws_subnet.dr_private_b.id] }
