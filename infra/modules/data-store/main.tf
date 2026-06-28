# DynamoDB Table for Incident States and Idempotency
resource "aws_dynamodb_table" "incident_state" {
  name         = "tf1-cdo05-${var.env}-incident-state"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "incident_id"

  attribute {
    name = "incident_id"
    type = "S"
  }

  attribute {
    name = "correlation_key"
    type = "S"
  }

  attribute {
    name = "alert_fingerprint"
    type = "S"
  }

  global_secondary_index {
    name            = "CorrelationAlertIndex"
    hash_key        = "correlation_key"
    range_key       = "alert_fingerprint"
    projection_type = "ALL"
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name        = "tf1-cdo05-${var.env}-incident-state"
    Environment = var.env
    Project     = "tf1-cdo05"
  }
}

# S3 Bucket for Incident Artifacts / Evidence
resource "aws_s3_bucket" "artifacts" {
  bucket        = "tf1-cdo05-${var.env}-incident-artifacts"
  force_destroy = var.env == "sandbox" ? true : false

  object_lock_enabled = var.enable_s3_object_lock

  tags = {
    Name        = "tf1-cdo05-${var.env}-incident-artifacts"
    Environment = var.env
    Project     = "tf1-cdo05"
  }
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    id     = "archive_and_cleanup"
    status = "Enabled"

    filter {}

    transition {
      days          = var.s3_retention_days
      storage_class = "STANDARD_IA"
    }

    expiration {
      days = 90
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

# Bucket Policy to enforce SSL/TLS (Deny non-TLS transport)
resource "aws_s3_bucket_policy" "artifacts_security_policy" {
  bucket = aws_s3_bucket.artifacts.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnforceTLSRequests"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.artifacts.arn,
          "${aws_s3_bucket.artifacts.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}
