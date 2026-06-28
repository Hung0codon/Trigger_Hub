output "sns_topic_arn" {
  value       = aws_sns_topic.alerts.arn
  description = "ARN của AWS SNS Topic dùng để gửi thông báo khẩn cấp"
}
