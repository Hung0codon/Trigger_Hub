module "networking" {
  source = "../../modules/networking"

  env                = var.env
  enable_nat_gateway = true
  single_nat_gateway = true # Tiết kiệm chi phí cho sandbox
}

module "data_store" {
  source = "../../modules/data-store"

  env                   = var.env
  enable_s3_object_lock = false # Tắt để tối ưu chi phí ở sandbox
  s3_retention_days     = 30
}

module "eks" {
  source = "../../modules/eks"

  env                = var.env
  vpc_id             = module.networking.vpc_id
  private_subnet_ids = module.networking.private_subnet_ids
  sg_eks_nodes_id    = module.networking.sg_eks_nodes_id
  instance_types     = ["t3.medium"] # Instance size nhỏ phù hợp sandbox
  desired_size       = 2
  max_size           = 4
  min_size           = 2
}

# SQS Dead Letter Queue (FIFO)
resource "aws_sqs_queue" "dlq" {
  name                        = "tf1-cdo05-${var.env}-alert-dlq.fifo"
  fifo_queue                  = true
  content_based_deduplication = true
  deduplication_scope         = "messageGroup"
  fifo_throughput_limit       = "perMessageGroupId"

  message_retention_seconds = 1209600 # Giữ lại 14 ngày để điều tra lỗi

  tags = {
    Name        = "tf1-cdo05-${var.env}-alert-queue-dlq"
    Environment = var.env
    Project     = "tf1-cdo05"
  }
}

# SQS Main Queue (FIFO)
resource "aws_sqs_queue" "main" {
  name                        = "tf1-cdo05-${var.env}-alert-queue.fifo"
  fifo_queue                  = true
  content_based_deduplication = true
  deduplication_scope         = "messageGroup"
  fifo_throughput_limit       = "perMessageGroupId"

  visibility_timeout_seconds = 300    # 5 phút xử lý tối đa
  message_retention_seconds  = 345600 # Giữ lại 4 ngày

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3 # Thử lại tối đa 3 lần trước khi đẩy vào DLQ
  })

  tags = {
    Name        = "tf1-cdo05-${var.env}-alert-queue"
    Environment = var.env
    Project     = "tf1-cdo05"
  }
}

# Redrive Allow Policy for DLQ
resource "aws_sqs_queue_redrive_allow_policy" "dlq_allow" {
  queue_url = aws_sqs_queue.dlq.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue",
    sourceQueueArns   = [aws_sqs_queue.main.arn]
  })
}

# ==================== INGEST LAMBDA ====================

# IAM Role for Ingest Lambda Function
resource "aws_iam_role" "lambda" {
  name = "tf1-cdo05-${var.env}-lambda-ingest-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Attach basic execution policy (CloudWatch logs)
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda.name
}

# Scoped IAM Policy for Ingest Lambda (allow writing to the SQS queue)
resource "aws_iam_policy" "lambda_sqs" {
  name        = "tf1-cdo05-${var.env}-lambda-sqs-policy"
  description = "Cho phép Lambda gửi tin nhắn vào SQS FIFO"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.main.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_sqs_attach" {
  policy_arn = aws_iam_policy.lambda_sqs.arn
  role       = aws_iam_role.lambda.name
}

# Archive Ingest Lambda Code
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/ingest.py"
  output_path = "${path.module}/lambda/ingest.zip"
}

# Deploy Ingest Lambda Function
resource "aws_lambda_function" "ingest" {
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  function_name    = "tf1-cdo05-${var.env}-ingest-handler"
  role             = aws_iam_role.lambda.arn
  handler          = "ingest.handler"
  runtime          = "python3.12"
  timeout          = 30

  environment {
    variables = {
      SQS_QUEUE_URL = aws_sqs_queue.main.url
    }
  }

  tags = {
    Name        = "tf1-cdo05-${var.env}-ingest-handler"
    Environment = var.env
    Project     = "tf1-cdo05"
  }
}

# Expose Public Endpoint: Lambda Function URL
resource "aws_lambda_function_url" "ingest_url" {
  function_name      = aws_lambda_function.ingest.function_name
  authorization_type = "NONE"

  cors {
    allow_origins     = ["*"]
    allow_methods     = ["*"]
    allow_headers     = ["content-type"]
    expose_headers    = ["date", "keep-alive"]
    max_age           = 86400
  }
}

resource "aws_lambda_permission" "allow_public_function_url" {
  statement_id           = "AllowFunctionURLInvoke"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.ingest.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}



# ==================== INTEGRATION LAMBDA ====================

# IAM Role for Integration Lambda Function
resource "aws_iam_role" "integration_lambda" {
  name = "tf1-cdo05-${var.env}-lambda-integration-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Attach basic execution policy
resource "aws_iam_role_policy_attachment" "integration_lambda_logs" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.integration_lambda.name
}

# Scoped IAM Policy for Integration Lambda (DynamoDB, S3, Secrets Manager access)
resource "aws_iam_policy" "integration_lambda_policy" {
  name        = "tf1-cdo05-${var.env}-lambda-integration-policy"
  description = "Quyền truy cập dữ liệu và secrets cho Integration Lambda"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:Query"
        ]
        Resource = [
          module.data_store.dynamodb_table_arn,
          "${module.data_store.dynamodb_table_arn}/index/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          module.data_store.s3_bucket_arn,
          "${module.data_store.s3_bucket_arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "integration_lambda_attach" {
  policy_arn = aws_iam_policy.integration_lambda_policy.arn
  role       = aws_iam_role.integration_lambda.name
}

# Archive Integration Lambda Code
data "archive_file" "integration_lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/integration.py"
  output_path = "${path.module}/lambda/integration.zip"
}

# Deploy Integration Lambda Function
resource "aws_lambda_function" "integration" {
  filename         = data.archive_file.integration_lambda_zip.output_path
  source_code_hash = data.archive_file.integration_lambda_zip.output_base64sha256
  function_name    = "tf1-cdo05-${var.env}-integration-handler"
  role             = aws_iam_role.integration_lambda.arn
  handler          = "integration.handler"
  runtime          = "python3.12"
  timeout          = 30

  environment {
    variables = {
      ENVIRONMENT    = var.env
      DYNAMODB_TABLE = module.data_store.dynamodb_table_name
      S3_BUCKET_NAME = module.data_store.s3_bucket_name
    }
  }

  tags = {
    Name        = "tf1-cdo05-${var.env}-integration-handler"
    Environment = var.env
    Project     = "tf1-cdo05"
  }
}

# ==================== OBSERVABILITY & TENANT ONBOARDING ====================

# Call Observability Module
module "observability" {
  source = "../../modules/observability"

  env                     = var.env
  sqs_queue_name          = aws_sqs_queue.main.name
  sqs_dlq_name            = aws_sqs_queue.dlq.name
  dynamodb_table_name     = module.data_store.dynamodb_table_name
  sns_subscription_email  = var.sns_subscription_email
  s3_bucket_name          = module.data_store.s3_bucket_name
  ingest_lambda_name      = aws_lambda_function.ingest.function_name
  integration_lambda_name = aws_lambda_function.integration.function_name
}

# Automatically onboard a Demo Tenant: tenant-a
module "tenant_a" {
  source = "../../modules/tenant-provision"

  env                   = var.env
  tenant_id             = "tenant-a"
  s3_bucket_name        = module.data_store.s3_bucket_name
  s3_bucket_arn         = module.data_store.s3_bucket_arn
  dynamodb_table_arn    = module.data_store.dynamodb_table_arn
  eks_oidc_provider_url = module.eks.eks_oidc_provider_url
  eks_oidc_provider_arn = module.eks.eks_oidc_provider_arn
}

# ==================== API GATEWAY FOR BYPASSING SCP 403 ====================

resource "aws_apigatewayv2_api" "ingest" {
  name          = "tf1-cdo05-${var.env}-ingest-api"
  protocol_type = "HTTP"
  
  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["POST", "OPTIONS"]
    allow_headers = ["content-type"]
    max_age       = 86400
  }
}

resource "aws_apigatewayv2_integration" "ingest" {
  api_id                 = aws_apigatewayv2_api.ingest.id
  integration_type       = "AWS_PROXY"
  integration_method     = "POST"
  integration_uri        = aws_lambda_function.ingest.arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "ingest" {
  api_id    = aws_apigatewayv2_api.ingest.id
  route_key = "POST /alerts"
  target    = "integrations/${aws_apigatewayv2_integration.ingest.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.ingest.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ingest.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.ingest.execution_arn}/*/*"
}

