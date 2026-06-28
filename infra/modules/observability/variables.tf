variable "env" {
  type        = string
  description = "Môi trường triển khai (ví dụ: sandbox, staging, prod)"
}

variable "sqs_queue_name" {
  type        = string
  description = "Tên của hàng đợi SQS chính để theo dõi số lượng tin nhắn"
}

variable "sqs_dlq_name" {
  type        = string
  description = "Tên của hàng đợi SQS Dead Letter Queue để theo dõi lỗi"
}

variable "dynamodb_table_name" {
  type        = string
  description = "Tên của bảng DynamoDB incident state để theo dõi throttling"
}

variable "sns_subscription_email" {
  type        = string
  description = "Địa chỉ email của SRE để đăng ký nhận cảnh báo qua SNS"
}

variable "s3_bucket_name" {
  type        = string
  description = "Tên của S3 bucket lưu trữ artifacts để theo dõi lỗi"
}

variable "ingest_lambda_name" {
  type        = string
  description = "Tên của Ingest Lambda function để theo dõi lỗi và duration"
}

variable "integration_lambda_name" {
  type        = string
  description = "Tên của Integration Lambda function để theo dõi lỗi và duration"
}
