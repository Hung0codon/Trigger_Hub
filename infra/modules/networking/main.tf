data "aws_region" "current" {}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = "tf1-cdo05-${var.env}-networking-vpc"
    Environment = var.env
    Project     = "tf1-cdo05"
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name        = "tf1-cdo05-${var.env}-networking-igw"
    Environment = var.env
    Project     = "tf1-cdo05"
  }
}

# Public Subnets
resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name                                                     = "tf1-cdo05-${var.env}-networking-subnet-public-${count.index + 1}"
    Environment                                              = var.env
    Project                                                  = "tf1-cdo05"
    "kubernetes.io/role/elb"                                 = "1"
    "kubernetes.io/cluster/tf1-cdo05-${var.env}-eks-cluster" = "shared"
  }
}

# Private Subnets
resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name                                                     = "tf1-cdo05-${var.env}-networking-subnet-private-${count.index + 1}"
    Environment                                              = var.env
    Project                                                  = "tf1-cdo05"
    "kubernetes.io/role/internal-elb"                        = "1"
    "kubernetes.io/cluster/tf1-cdo05-${var.env}-eks-cluster" = "shared"
  }
}

# NAT Gateway EIP
resource "aws_eip" "nat" {
  count  = var.enable_nat_gateway ? (var.single_nat_gateway ? 1 : length(var.public_subnet_cidrs)) : 0
  domain = "vpc"

  tags = {
    Name        = "tf1-cdo05-${var.env}-networking-nat-eip-${count.index + 1}"
    Environment = var.env
    Project     = "tf1-cdo05"
  }
}

# NAT Gateways
resource "aws_nat_gateway" "this" {
  count         = var.enable_nat_gateway ? (var.single_nat_gateway ? 1 : length(var.public_subnet_cidrs)) : 0
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name        = "tf1-cdo05-${var.env}-networking-nat-gw-${count.index + 1}"
    Environment = var.env
    Project     = "tf1-cdo05"
  }

  depends_on = [aws_internet_gateway.this]
}

# Public Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name        = "tf1-cdo05-${var.env}-networking-rt-public"
    Environment = var.env
    Project     = "tf1-cdo05"
  }
}

# Private Route Tables
resource "aws_route_table" "private" {
  count  = length(var.private_subnet_cidrs)
  vpc_id = aws_vpc.this.id

  dynamic "route" {
    for_each = var.enable_nat_gateway ? [1] : []
    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = var.single_nat_gateway ? aws_nat_gateway.this[0].id : aws_nat_gateway.this[count.index].id
    }
  }

  tags = {
    Name        = "tf1-cdo05-${var.env}-networking-rt-private-${count.index + 1}"
    Environment = var.env
    Project     = "tf1-cdo05"
  }
}

# Route Table Associations for Public Subnets
resource "aws_route_table_association" "public" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Route Table Associations for Private Subnets
resource "aws_route_table_association" "private" {
  count          = length(var.private_subnet_cidrs)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# ==================== SECURITY GROUPS ====================

# Security Group for Application Load Balancer
resource "aws_security_group" "alb" {
  name        = "tf1-cdo05-${var.env}-sg-alb"
  description = "Security group for Application Load Balancer"
  vpc_id      = aws_vpc.this.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "tf1-cdo05-${var.env}-sg-alb"
    Environment = var.env
  }
}

# Security Group for EKS Worker Nodes
resource "aws_security_group" "eks_nodes" {
  name        = "tf1-cdo05-${var.env}-sg-eks-nodes"
  description = "Security group for EKS worker nodes"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "Allow traffic from ALB on application ports"
    from_port       = 1025
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description = "Allow node-to-node traffic inside SG"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name                                                     = "tf1-cdo05-${var.env}-sg-eks-nodes"
    Environment                                              = var.env
    "kubernetes.io/cluster/tf1-cdo05-${var.env}-eks-cluster" = "owned"
  }
}

# Security Group for Lambda Functions
resource "aws_security_group" "lambda" {
  name        = "tf1-cdo05-${var.env}-sg-lambda"
  description = "Security group for Lambda functions in VPC"
  vpc_id      = aws_vpc.this.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "tf1-cdo05-${var.env}-sg-lambda"
    Environment = var.env
  }
}

# Security Group for VPC Endpoints
resource "aws_security_group" "vpc_endpoints" {
  name        = "tf1-cdo05-${var.env}-sg-vpc-endpoints"
  description = "Security group for VPC Interface Endpoints"
  vpc_id      = aws_vpc.this.id

  ingress {
    from_port = 443
    to_port   = 443
    protocol  = "tcp"
    security_groups = [
      aws_security_group.eks_nodes.id,
      aws_security_group.lambda.id
    ]
  }

  tags = {
    Name        = "tf1-cdo05-${var.env}-sg-vpc-endpoints"
    Environment = var.env
  }
}

# ==================== VPC ENDPOINTS ====================

# VPC Gateway Endpoint for S3
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = concat(
    [aws_route_table.public.id],
    aws_route_table.private[*].id
  )

  tags = {
    Name        = "tf1-cdo05-${var.env}-networking-vpce-s3"
    Environment = var.env
  }
}

# VPC Gateway Endpoint for DynamoDB
resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.dynamodb"
  vpc_endpoint_type = "Gateway"

  route_table_ids = concat(
    [aws_route_table.public.id],
    aws_route_table.private[*].id
  )

  tags = {
    Name        = "tf1-cdo05-${var.env}-networking-vpce-dynamodb"
    Environment = var.env
  }
}

# VPC Interface Endpoint for SQS
resource "aws_vpc_endpoint" "sqs" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.sqs"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]

  tags = {
    Name        = "tf1-cdo05-${var.env}-networking-vpce-sqs"
    Environment = var.env
  }
}

# VPC Interface Endpoint for ECR API
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ecr.api"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]

  tags = {
    Name        = "tf1-cdo05-${var.env}-networking-vpce-ecr-api"
    Environment = var.env
  }
}

# VPC Interface Endpoint for ECR DKR
resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]

  tags = {
    Name        = "tf1-cdo05-${var.env}-networking-vpce-ecr-dkr"
    Environment = var.env
  }
}

# VPC Interface Endpoint for CloudWatch Logs
resource "aws_vpc_endpoint" "logs" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.logs"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]

  tags = {
    Name        = "tf1-cdo05-${var.env}-networking-vpce-logs"
    Environment = var.env
  }
}

# VPC Interface Endpoint for STS
resource "aws_vpc_endpoint" "sts" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.sts"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]

  tags = {
    Name        = "tf1-cdo05-${var.env}-networking-vpce-sts"
    Environment = var.env
  }
}

# VPC Interface Endpoint for Secrets Manager
resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]

  tags = {
    Name        = "tf1-cdo05-${var.env}-networking-vpce-secretsmanager"
    Environment = var.env
  }
}
