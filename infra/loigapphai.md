# Nhật Ký Lỗi Gặp Phải và Cách Khắc Phục

Tài liệu này ghi lại các lỗi phát sinh trong quá trình vận hành hạ tầng IaC (Terraform) và các bước xử lý tương ứng để làm tài liệu tham khảo cho đội ngũ.

---

## 1. Lỗi 403 Forbidden Khi Khởi Tạo Backend S3 (`terraform init`)

### Chi Tiết Lỗi (Error Message)
```text
│ Error: Error refreshing state: Unable to access object "sandbox/terraform.tfstate" in S3 bucket "tf1-cdo05-tfstate": 
│ operation error S3: HeadObject, https response error StatusCode: 403, RequestID: ..., HostID: ..., 
│ api error Forbidden: Forbidden
```

### Nguyên Nhân (Root Cause)
1. Tên S3 Bucket trong AWS là định danh **độc nhất toàn cầu (globally unique namespace)**.
2. Tên bucket mặc định gợi ý trong kế hoạch triển khai (`tf1-cdo05-tfstate`) đã bị một tài khoản AWS khác đăng ký từ trước trên hệ thống. 
3. Do bucket này thuộc sở hữu của một tài khoản AWS khác, tài khoản AWS hiện tại của bạn (`hung_admin`) không có quyền đọc/ghi dữ liệu vào đó, dẫn đến lỗi bảo mật **403 Forbidden**.

### Cách Khắc Phục (Solution)
Để khắc phục, chúng ta đã thực hiện cấp phát lại một S3 bucket mới đi kèm với Account ID của bạn để đảm bảo không bị trùng tên trên toàn hệ thống AWS:

#### Bước 1: Tạo S3 Bucket độc nhất mới trên AWS
Chạy lệnh tạo bucket ở vùng `us-east-1` kèm theo Account ID `945125812908`:
```powershell
aws s3api create-bucket --bucket tf1-cdo05-tfstate-945125812908 --region us-east-1
```

#### Bước 2: Cấu hình bảo mật nâng cao cho S3 Bucket
Bật các tính năng lưu vết lịch sử (Versioning), mã hóa dữ liệu (SSE-S3), và chặn quyền truy cập công khai (Block Public Access):
```powershell
# Bật Versioning
aws s3api put-bucket-versioning --bucket tf1-cdo05-tfstate-945125812908 --versioning-configuration Status=Enabled

# Bật Mã hóa mặc định
aws s3api put-bucket-encryption --bucket tf1-cdo05-tfstate-945125812908 --server-side-encryption-configuration '{\"Rules\": [{\"ApplyServerSideEncryptionByDefault\": {\"SSEAlgorithm\": \"AES256\"}}]}'

# Chặn truy cập công khai
aws s3api put-public-access-block --bucket tf1-cdo05-tfstate-945125812908 --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
```

#### Bước 3: Tạo DynamoDB Lock Table
Tạo bảng khóa trạng thái để tránh đụng độ dữ liệu khi có nhiều người chạy lệnh đồng thời:
```powershell
aws dynamodb create-table --table-name tf1-cdo05-tflock --attribute-definitions AttributeName=LockID,AttributeType=S --key-schema AttributeName=LockID,KeyType=HASH --billing-mode PAY_PER_REQUEST --region us-east-1
```

#### Bước 4: Đồng bộ hóa cấu hình trong mã nguồn (`backend.tf`)
Cập nhật thuộc tính `bucket` trong file `infra/environments/sandbox/backend.tf`:
```hcl
terraform {
  backend "s3" {
    bucket         = "tf1-cdo05-tfstate-945125812908" # Tên bucket độc nhất mới
    key            = "sandbox/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "tf1-cdo05-tflock"
    encrypt        = true
  }
}
```

#### Bước 5: Khởi tạo lại với cờ cấu hình mới (`-reconfigure`)
Chạy lệnh sau tại thư mục `infra/environments/sandbox/` để Terraform tải lại cấu hình backend mới:
```powershell
terraform init -reconfigure
```

**Kết quả**: Hệ thống thông báo `Successfully configured the backend "s3"! Terraform has been successfully initialized!` và sẵn sàng chạy lệnh `terraform plan`.

---

## 2. Lỗi Ký Tự Tiếng Việt (Unicode) Trong GroupDescription Của Security Group

### Chi Tiết Lỗi (Error Message)
```text
│ Error: creating Security Group (tf1-cdo05-sandbox-sg-alb): operation error EC2: CreateSecurityGroup, 
│ https response error StatusCode: 400, RequestID: 89b20017-fb1d-476b-abc0-6d7af9b09575, 
│ api error InvalidParameterValue: Value (Tường lửa kiểm soát lưu lượng đi vào Load Balancer) 
│ for parameter GroupDescription is invalid. Character sets beyond ASCII are not supported.
```

### Nguyên Nhân (Root Cause)
AWS EC2 API quy định tham số `GroupDescription` (Description - Mô tả của Security Group) chỉ hỗ trợ bộ ký tự chuẩn **ASCII (tiếng Anh không dấu)**. Việc khai báo các mô tả chứa ký tự Unicode tiếng Việt có dấu sẽ bị hệ thống AWS trả về lỗi HTTP 400 Bad Request (`InvalidParameterValue`).

### Cách Khắc Phục (Solution)
Cập nhật lại toàn bộ nội dung trường `description` trong tất cả các định nghĩa `aws_security_group` thành tiếng Anh chuẩn không dấu (ASCII):

1. Trong file [`infra/modules/networking/main.tf`](file:///d:/FIle_doc/Capstone_W11-12/infra/modules/networking/main.tf):
   * `aws_security_group.alb`: Đổi từ `"Tường lửa kiểm soát lưu lượng..."` sang `"Security group for Application Load Balancer"`.
   * `aws_security_group.eks_nodes`: Đổi từ `"Tường lửa cho các worker nodes..."` sang `"Security group for EKS worker nodes"`.
   * `aws_security_group.lambda`: Đổi từ `"Tường lửa cho các Lambda functions..."` sang `"Security group for Lambda functions in VPC"`.
   * `aws_security_group.vpc_endpoints`: Đổi từ `"Tường lửa cho VPC Interface Endpoints"` sang `"Security group for VPC Interface Endpoints"`.

2. Tiến hành chạy lại lệnh áp dụng:
   ```powershell
   terraform apply -auto-approve
   ```

---

## 3. Lỗi EKS Node Group Triển Khai Thất Bại (NodeCreationFailure - Unhealthy nodes in the kubernetes cluster)

### Chi Tiết Lỗi (Error Message)
```text
│ Error: waiting for EKS Node Group (tf1-cdo05-sandbox-eks-cluster:tf1-cdo05-sandbox-eks-node-group) create: 
│ unexpected state 'CREATE_FAILED', wanted target 'ACTIVE'. 
│ last error: ..., ...: NodeCreationFailure: Unhealthy nodes in the kubernetes cluster
```

### Nguyên Nhân (Root Cause)
1. Cụm EKS Control Plane được gán Security Group riêng `sg-eks-nodes` thông qua tham số `security_group_ids` trong khối `vpc_config` của resource `aws_eks_cluster`.
2. Do sử dụng EKS Managed Node Group mặc định mà không cấu hình Custom Launch Template, các máy ảo EC2 worker nodes chỉ được gán Security Group mặc định (Primary Security Group) do EKS tự sinh ra.
3. Vì `sg-eks-nodes` chỉ cho phép lưu lượng từ `sg-alb` và chính nó (`self = true`), nó đã chặn hoàn toàn các yêu cầu kết nối trên cổng `443` và `10250` đi từ các EC2 worker nodes (đang mang Primary Security Group) tới EKS Control Plane. 
4. Hậu quả là các EC2 instances không thể bắt tay (handshake) và đăng ký gia nhập cụm Kubernetes thành công, dẫn đến lỗi Nodes Unhealthy sau 30-40 phút chờ đợi.

### Cách Khắc Phục (Solution)
Cần gán đồng thời cả Custom Security Group (`sg-eks-nodes`) và EKS Primary Security Group cho các worker nodes để đảm bảo luồng giao tiếp thông suốt. Cách cấu hình chuẩn:

1. Định nghĩa thêm **Launch Template** cho EC2 Worker Nodes trong [`infra/modules/eks/main.tf`](file:///d:/FIle_doc/Capstone_W11-12/infra/modules/eks/main.tf):
   ```hcl
   resource "aws_launch_template" "node" {
     name_prefix   = "tf1-cdo05-${var.env}-eks-node-"
     instance_type = var.instance_types[0]

     vpc_security_group_ids = [
       var.sg_eks_nodes_id,
       aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
     ]
     ...
   }
   ```
2. Gắn Launch Template này vào tài nguyên Node Group `aws_eks_node_group.this`:
   ```hcl
   resource "aws_eks_node_group" "this" {
     ...
     launch_template {
       name    = aws_launch_template.node.name
       version = aws_launch_template.node.latest_version
     }
   }
   ```
3. Do cụm EKS cũ và các máy ảo cũ đang ở trạng thái lỗi/không sạch, chạy lệnh sau để xóa các tài nguyên lỗi trước khi apply lại (lưu ý dùng dấu nháy kép cho target trong PowerShell):
   ```powershell
   terraform destroy -target="module.eks" -auto-approve
   ```
   Sau đó tiến hành chạy lại lệnh apply để khởi tạo mới an toàn:
   ```powershell
   terraform apply -auto-approve
   ```



