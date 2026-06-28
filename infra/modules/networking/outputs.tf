output "vpc_id" {
  value       = aws_vpc.this.id
  description = "ID của VPC được tạo"
}

output "public_subnet_ids" {
  value       = aws_subnet.public[*].id
  description = "Danh sách IDs của các public subnets"
}

output "private_subnet_ids" {
  value       = aws_subnet.private[*].id
  description = "Danh sách IDs của các private subnets"
}

output "vpc_cidr_block" {
  value       = aws_vpc.this.cidr_block
  description = "CIDR block của VPC"
}

output "sg_alb_id" {
  value       = aws_security_group.alb.id
  description = "Security Group ID cho ALB"
}

output "sg_eks_nodes_id" {
  value       = aws_security_group.eks_nodes.id
  description = "Security Group ID cho EKS Worker Nodes"
}

output "sg_lambda_id" {
  value       = aws_security_group.lambda.id
  description = "Security Group ID cho Lambda Functions"
}

output "sg_vpc_endpoints_id" {
  value       = aws_security_group.vpc_endpoints.id
  description = "Security Group ID cho VPC Endpoints"
}
