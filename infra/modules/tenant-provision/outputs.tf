output "tenant_namespace" {
  value       = kubernetes_namespace.tenant.metadata[0].name
  description = "Kubernetes Namespace dành riêng cho tenant"
}

output "tenant_service_account_name" {
  value       = kubernetes_service_account.tenant_sa.metadata[0].name
  description = "Kubernetes Service Account đã được tạo cho tenant"
}

output "tenant_iam_role_arn" {
  value       = aws_iam_role.tenant_irsa.arn
  description = "ARN của IAM Role cô lập dữ liệu gắn với Service Account của tenant"
}
