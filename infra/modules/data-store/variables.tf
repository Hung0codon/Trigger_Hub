variable "env" {
  type        = string
  description = "Môi trường triển khai (ví dụ: sandbox, staging, prod)"
}

variable "enable_s3_object_lock" {
  type        = bool
  description = "Bật Object Lock trên S3 bucket cho tính bất biến của bằng chứng kiểm toán (audit trail)"
  default     = false
}

variable "s3_retention_days" {
  type        = number
  description = "Số ngày giữ lại bằng chứng trên S3 trước khi chuyển sang Infrequent Access hoặc xóa"
  default     = 30
}
