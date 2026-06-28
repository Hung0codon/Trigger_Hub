variable "env" {
  type        = string
  description = "Môi trường triển khai (ví dụ: sandbox, staging, prod)"
}

variable "tenant_id" {
  type        = string
  description = "ID duy nhất định danh cho Tenant (ví dụ: tenant-a, tenant-b)"
}

variable "s3_bucket_name" {
  type        = string
  description = "Tên của S3 bucket dùng chung chứa incident artifacts"
}

variable "s3_bucket_arn" {
  type        = string
  description = "ARN của S3 bucket dùng chung chứa incident artifacts"
}

variable "dynamodb_table_arn" {
  type        = string
  description = "ARN của bảng DynamoDB dùng chung chứa incident state"
}

variable "eks_oidc_provider_url" {
  type        = string
  description = "URL của OIDC provider trên EKS dùng cho IRSA"
}

variable "eks_oidc_provider_arn" {
  type        = string
  description = "ARN của IAM OIDC provider dùng cho IRSA"
}
