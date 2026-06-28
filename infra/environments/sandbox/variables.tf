variable "aws_region" {
  type        = string
  description = "AWS Region to deploy resources"
  default     = "us-east-1"
}


variable "env" {
  type        = string
  description = "Môi trường hiện tại"
  default     = "sandbox"
}

variable "sns_subscription_email" {
  type        = string
  description = "Email nhận thông báo cảnh báo SRE"
  default     = ""
}
