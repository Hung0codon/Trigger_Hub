output "vpc_id" {
  value       = module.networking.vpc_id
  description = "VPC ID of the sandbox environment"
}

output "eks_cluster_name" {
  value       = module.eks.cluster_name
  description = "EKS Cluster Name"
}

output "eks_cluster_endpoint" {
  value       = module.eks.cluster_endpoint
  description = "EKS Cluster API Server Endpoint"
}

output "ingest_lambda_url" {
  value       = aws_lambda_function_url.ingest_url.function_url
  description = "Public HTTP Endpoint for Alertmanager Webhook"
}

output "sqs_main_queue_url" {
  value       = aws_sqs_queue.main.url
  description = "SQS Main Queue URL"
}

output "sqs_dlq_queue_url" {
  value       = aws_sqs_queue.dlq.url
  description = "SQS DLQ Queue URL"
}

output "dynamodb_table_name" {
  value       = module.data_store.dynamodb_table_name
  description = "DynamoDB table name for incident states"
}

output "s3_bucket_name" {
  value       = module.data_store.s3_bucket_name
  description = "S3 bucket name for incident artifacts"
}

output "tenant_a_namespace" {
  value       = module.tenant_a.tenant_namespace
  description = "Kubernetes Namespace allocated for Tenant A"
}

output "tenant_a_service_account" {
  value       = module.tenant_a.tenant_service_account_name
  description = "Kubernetes Service Account allocated for Tenant A"
}

output "tenant_a_iam_role_arn" {
  value       = module.tenant_a.tenant_iam_role_arn
  description = "IAM Role ARN with isolated data access rules for Tenant A"
}

output "ingest_apigateway_url" {
  value       = "${aws_apigatewayv2_stage.default.invoke_url}alerts"
  description = "API Gateway Endpoint for Alertmanager Webhook (Bypasses Lambda Function URL SCP)"
}

