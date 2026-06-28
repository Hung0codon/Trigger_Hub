# SNS Topic for Incident Pipeline Alarms
resource "aws_sns_topic" "alerts" {
  name = "tf1-cdo05-${var.env}-alerts-topic"

  tags = {
    Name        = "tf1-cdo05-${var.env}-alerts-topic"
    Environment = var.env
    Project     = "tf1-cdo05"
  }
}

# Email subscription for on-call SRE
resource "aws_sns_topic_subscription" "email" {
  count     = var.sns_subscription_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.sns_subscription_email
}

# CloudWatch Alarm: SQS DLQ has message (POISON MESSAGES DETECTED)
resource "aws_cloudwatch_metric_alarm" "sqs_dlq_has_messages" {
  alarm_name          = "tf1-cdo05-${var.env}-sqs-dlq-messages-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Cảnh báo khẩn cấp: Hàng đợi lỗi DLQ có tin nhắn lỗi không thể xử lý!"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    QueueName = var.sqs_dlq_name
  }
}

# CloudWatch Alarm: SQS Backlog count is high
resource "aws_cloudwatch_metric_alarm" "sqs_backlog" {
  alarm_name          = "tf1-cdo05-${var.env}-sqs-backlog-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Maximum"
  threshold           = 100
  alarm_description   = "Cảnh báo nghẽn mạng: Số lượng tin nhắn chờ xử lý trong queue vượt quá 100!"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    QueueName = var.sqs_queue_name
  }
}

# CloudWatch Alarm: SQS Message Age is high (latency is high)
resource "aws_cloudwatch_metric_alarm" "sqs_message_age" {
  alarm_name          = "tf1-cdo05-${var.env}-sqs-message-age-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateAgeOfOldestMessage"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Maximum"
  threshold           = 300
  alarm_description   = "Độ trễ cao: Cảnh báo tin nhắn cũ nhất trong queue đã tồn tại quá 5 phút!"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    QueueName = var.sqs_queue_name
  }
}

# CloudWatch Alarm: DynamoDB Read Throttling
resource "aws_cloudwatch_metric_alarm" "dynamodb_read_throttled" {
  alarm_name          = "tf1-cdo05-${var.env}-dynamodb-read-throttled-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ReadThrottleEvents"
  namespace           = "AWS/DynamoDB"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Quá tải DynamoDB: Có hiện tượng Throttling đọc dữ liệu xảy ra trên bảng incident-state!"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    TableName = var.dynamodb_table_name
  }
}

# CloudWatch Alarm: DynamoDB Write Throttling
resource "aws_cloudwatch_metric_alarm" "dynamodb_write_throttled" {
  alarm_name          = "tf1-cdo05-${var.env}-dynamodb-write-throttled-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "WriteThrottleEvents"
  namespace           = "AWS/DynamoDB"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Quá tải DynamoDB: Có hiện tượng Throttling ghi dữ liệu xảy ra trên bảng incident-state!"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    TableName = var.dynamodb_table_name
  }
}

# CloudWatch Alarm: DynamoDB Combined ThrottledRequests
resource "aws_cloudwatch_metric_alarm" "dynamodb_throttles" {
  alarm_name          = "tf1-cdo05-${var.env}-dynamodb-throttles-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ThrottledRequests"
  namespace           = "AWS/DynamoDB"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Quá tải DynamoDB: Có yêu cầu bị Throttle trên bảng incident-state!"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    TableName = var.dynamodb_table_name
  }
}

# CloudWatch Alarm: Lambda Ingest Errors
resource "aws_cloudwatch_metric_alarm" "lambda_ingest_errors" {
  alarm_name          = "tf1-cdo05-${var.env}-lambda-ingest-errors-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "Cảnh báo lỗi: Ingest Lambda Function có số lỗi > 5 trong 5 phút!"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    FunctionName = var.ingest_lambda_name
  }
}

# CloudWatch Alarm: Lambda Ingest Duration
resource "aws_cloudwatch_metric_alarm" "lambda_ingest_duration" {
  alarm_name          = "tf1-cdo05-${var.env}-lambda-ingest-duration-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = 300
  extended_statistic  = "p99"
  threshold           = 10000 # 10s in ms
  alarm_description   = "Hiệu năng giảm: p99 Duration của Ingest Lambda > 10s!"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    FunctionName = var.ingest_lambda_name
  }
}

# CloudWatch Alarm: Lambda Integration Errors
resource "aws_cloudwatch_metric_alarm" "lambda_integration_errors" {
  alarm_name          = "tf1-cdo05-${var.env}-lambda-integration-errors-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "Cảnh báo lỗi: Integration Lambda Function có số lỗi > 5 trong 5 phút!"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    FunctionName = var.integration_lambda_name
  }
}

# CloudWatch Alarm: Lambda Integration Duration
resource "aws_cloudwatch_metric_alarm" "lambda_integration_duration" {
  alarm_name          = "tf1-cdo05-${var.env}-lambda-integration-duration-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = 300
  extended_statistic  = "p99"
  threshold           = 10000 # 10s in ms
  alarm_description   = "Hiệu năng giảm: p99 Duration của Integration Lambda > 10s!"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    FunctionName = var.integration_lambda_name
  }
}

# CloudWatch Alarm: S3 Bucket 4xx Errors
resource "aws_cloudwatch_metric_alarm" "s3_4xx_errors" {
  alarm_name          = "tf1-cdo05-${var.env}-s3-4xx-errors-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "4xxErrors"
  namespace           = "AWS/S3"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "Lỗi S3: Số lượng 4xx Errors của S3 bucket > 10 trong 5 phút!"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    BucketName = var.s3_bucket_name
    FilterId   = "EntireBucket"
  }
}

# CloudWatch Alarm: S3 Bucket 5xx Errors
resource "aws_cloudwatch_metric_alarm" "s3_5xx_errors" {
  alarm_name          = "tf1-cdo05-${var.env}-s3-5xx-errors-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "5xxErrors"
  namespace           = "AWS/S3"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "Lỗi S3: Số lượng 5xx Errors của S3 bucket > 10 trong 5 phút!"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    BucketName = var.s3_bucket_name
    FilterId   = "EntireBucket"
  }
}
