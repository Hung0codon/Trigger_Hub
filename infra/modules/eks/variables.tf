variable "env" {
  type        = string
  description = "Môi trường triển khai (ví dụ: sandbox, staging, prod)"
}

variable "vpc_id" {
  type        = string
  description = "ID của VPC để deploy cụm EKS"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Danh sách IDs các private subnets để đặt các worker nodes của EKS"
}

variable "sg_eks_nodes_id" {
  type        = string
  description = "Security Group ID cho EKS Worker Nodes"
}

variable "instance_types" {
  type        = list(string)
  description = "Danh sách các loại EC2 instance làm worker nodes"
  default     = ["t3.medium"]
}

variable "desired_size" {
  type        = number
  description = "Số lượng worker nodes mong muốn khởi chạy ban đầu"
  default     = 2
}

variable "max_size" {
  type        = number
  description = "Số lượng worker nodes tối đa trong Auto Scaling Group"
  default     = 4
}

variable "min_size" {
  type        = number
  description = "Số lượng worker nodes tối thiểu trong Auto Scaling Group"
  default     = 2
}
