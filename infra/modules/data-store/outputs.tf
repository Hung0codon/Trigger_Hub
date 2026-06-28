output "dynamodb_table_name" {
  value       = aws_dynamodb_table.incident_state.name
  description = "Tên của bảng DynamoDB lưu trữ incident state"
}

output "dynamodb_table_arn" {
  value       = aws_dynamodb_table.incident_state.arn
  description = "ARN của bảng DynamoDB lưu trữ incident state"
}

output "s3_bucket_name" {
  value       = aws_s3_bucket.artifacts.id
  description = "Tên của S3 bucket lưu trữ incident artifacts"
}

output "s3_bucket_arn" {
  value       = aws_s3_bucket.artifacts.arn
  description = "ARN của S3 bucket lưu trữ incident artifacts"
}
