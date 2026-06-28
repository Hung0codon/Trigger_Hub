data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]

  tags = {
    Name = "tf1-cdo05-github-oidc-provider"
    Env  = var.env
  }
}

resource "aws_iam_role" "github_actions" {
  name = "tf1-cdo05-github-actions-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:Hung0codon/Trigger_Hub:*"
          }
        }
      }
    ]
  })

  tags = {
    Name = "tf1-cdo05-github-actions-role"
    Env  = var.env
  }
}

resource "aws_iam_role_policy" "github_actions_policy" {
  name = "tf1-cdo05-github-actions-policy"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:*",
          "eks:*",
          "iam:*",
          "s3:*",
          "dynamodb:*",
          "ec2:*",
          "lambda:*",
          "logs:*",
          "sns:*",
          "sqs:*",
          "cloudwatch:*",
          "apigateway:*",
          "kms:*"
        ]
        Resource = "*"
      }
    ]
  })
}
