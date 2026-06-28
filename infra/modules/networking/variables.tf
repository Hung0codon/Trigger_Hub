variable "env" {
  type        = string
  description = "Môi trường triển khai (ví dụ: sandbox, staging, prod)"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block cho VPC"
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "Danh sách CIDR blocks cho public subnets (cần 3 subnets cho 3 AZs)"
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "Danh sách CIDR blocks cho private subnets (cần 3 subnets cho 3 AZs)"
  default     = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]
}

variable "availability_zones" {
  type        = list(string)
  description = "Danh sách các Availability Zones sử dụng"
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}


variable "enable_nat_gateway" {
  type        = bool
  description = "Có bật NAT Gateway hay không (sandbox có thể dùng 1 NAT để tiết kiệm chi phí)"
  default     = true
}

variable "single_nat_gateway" {
  type        = bool
  description = "Có sử dụng 1 NAT Gateway duy nhất cho tất cả AZs để tiết kiệm chi phí hay không"
  default     = true
}
