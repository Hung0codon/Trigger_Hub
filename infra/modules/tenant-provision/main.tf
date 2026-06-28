# Scoped IAM Policy: Restricts access to the tenant's prefix in the shared S3 bucket
resource "aws_iam_policy" "tenant_scoped_policy" {
  name        = "tf1-cdo05-${var.env}-${var.tenant_id}-scoped-policy"
  description = "Chính sách bảo mật cô lập dữ liệu cho tenant ${var.tenant_id}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Access to specific S3 folder
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:DeleteObject"
        ]
        Resource = [
          var.s3_bucket_arn,
          "${var.s3_bucket_arn}/${var.tenant_id}/*"
        ]
      },
      # Access to incident DynamoDB table
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          var.dynamodb_table_arn,
          "${var.dynamodb_table_arn}/index/*"
        ]
      }
    ]
  })
}

# IAM Role with Trust Relationship to EKS OIDC (IRSA)
resource "aws_iam_role" "tenant_irsa" {
  name = "tf1-cdo05-${var.env}-${var.tenant_id}-irsa-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = var.eks_oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(var.eks_oidc_provider_url, "https://", "")}:sub" = "system:serviceaccount:tf1-cdo05-${var.env}-${var.tenant_id}:tf1-cdo05-${var.env}-${var.tenant_id}-sa"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "tenant_irsa_attach" {
  policy_arn = aws_iam_policy.tenant_scoped_policy.arn
  role       = aws_iam_role.tenant_irsa.name
}

# Kubernetes Namespace for the Tenant
resource "kubernetes_namespace" "tenant" {
  metadata {
    name = "tf1-cdo05-${var.env}-${var.tenant_id}"
    labels = {
      tenant      = var.tenant_id
      environment = var.env
      tier        = "application"
    }
  }
}

# Kubernetes Service Account mapped to the Scoped IAM Role (IRSA)
resource "kubernetes_service_account" "tenant_sa" {
  metadata {
    name      = "tf1-cdo05-${var.env}-${var.tenant_id}-sa"
    namespace = kubernetes_namespace.tenant.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.tenant_irsa.arn
    }
  }
}

# Kubernetes Network Policy: Strict network isolation (default deny ingress)
resource "kubernetes_network_policy" "tenant_isolation" {
  metadata {
    name      = "tf1-cdo05-${var.env}-${var.tenant_id}-net-policy"
    namespace = kubernetes_namespace.tenant.metadata[0].name
  }

  spec {
    pod_selector {} # Áp dụng cho mọi pod trong namespace này

    ingress {
      from {
        pod_selector {} # Chỉ cho phép traffic đi vào từ các pod cùng namespace
      }
    }

    policy_types = ["Ingress"]
  }
}
