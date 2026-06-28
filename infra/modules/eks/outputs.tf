output "cluster_name" {
  value       = aws_eks_cluster.this.name
  description = "Tên của cụm EKS"
}

output "cluster_endpoint" {
  value       = aws_eks_cluster.this.endpoint
  description = "Địa chỉ API server endpoint của cụm EKS"
}

output "cluster_certificate_authority_data" {
  value       = aws_eks_cluster.this.certificate_authority[0].data
  description = "Dữ liệu CA certificate để kết nối tới cụm EKS"
}

output "eks_oidc_provider_url" {
  value       = aws_eks_cluster.this.identity[0].oidc[0].issuer
  description = "URL của OIDC provider trên EKS"
}

output "eks_oidc_provider_arn" {
  value       = aws_iam_openid_connect_provider.this.arn
  description = "ARN của IAM OIDC provider dùng cho IRSA"
}
