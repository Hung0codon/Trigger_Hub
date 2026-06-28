# Nhật Ký Triển Khai Hạ Tầng IaC (Terraform) - Bước Theo Bước

Tài liệu này ghi lại tuần tự chi tiết các bước khởi tạo tệp tin trong hệ thống Terraform IaC của dự án **Triage Hub**, kèm theo giải thích chi tiết lý do tại sao mỗi tệp được tạo theo thứ tự tương ứng, bám sát các yêu cầu của **Milestone 1** trong Deployment Plan.

---

## 1. Giai Đoạn Khởi Tạo Cấu Hình Môi Trường Root (`infra/environments/sandbox/`)

Giai đoạn này định hình khung làm việc (framework) cho Terraform trước khi xây dựng bất kỳ tài nguyên thực tế nào.

### Bước 1: Khai báo nhà cung cấp (`infra/environments/sandbox/providers.tf`)
* **Lý do cần trước**: Đây là tệp tin nền móng đầu tiên. Terraform không thể biên dịch hay hiểu bất kỳ khai báo tài nguyên nào nếu không biết cần tải xuống các provider (AWS, Kubernetes, TLS, Archive) phiên bản nào. Do đó, việc định cấu hình provider phải diễn ra trước nhất.
* **Chi tiết cấu trúc**:
  * Định nghĩa phiên bản Terraform tối thiểu (`>= 1.9.0`).
  * Yêu cầu các provider `aws` (~> 5.0) để quản lý AWS resource, `kubernetes` (~> 2.0) để deploy pod/namespace vào EKS, `tls` để phục vụ lấy fingerprint OIDC, và `archive` để nén file Lambda.
  * Cấu hình dynamic authentication cho `kubernetes` provider thông qua CLI `aws eks get-token` liên kết trực tiếp với đầu ra của cụm EKS.

### Bước 2: Cấu hình trạng thái từ xa (`infra/environments/sandbox/backend.tf`)
* **Lý do cần trước**: Ngay sau khi khai báo provider, Terraform cần biết nơi lưu trữ tệp trạng thái (state file) và cơ chế khóa trạng thái (state locking). Cấu hình này giúp ngăn chặn việc ghi đè trạng thái khi có nhiều kỹ sư cùng chạy lệnh `terraform apply`.
* **Chi tiết cấu trúc**:
  * Định nghĩa backend lưu trữ từ xa trên AWS S3 (`bucket = "tf1-cdo05-tfstate"`).
  * Định nghĩa vùng là `us-east-1` theo đúng **AI Contract**.
  * Định nghĩa bảng DynamoDB khóa trạng thái (`dynamodb_table = "tf1-cdo05-tflock"`).
  * Bật chế độ mã hóa trạng thái (`encrypt = true`).

### Bước 3: Định nghĩa các tham số đầu vào (`infra/environments/sandbox/variables.tf`)
* **Lý do cần trước**: Các tệp triển khai tài nguyên tiếp theo sẽ sử dụng các biến số chung này để cấu hình tên vùng (Region), môi trường (env), và thông tin liên lạc (email cảnh báo). Khai báo biến trước giúp các tệp tài nguyên phía sau không bị lỗi tham chiếu chưa định nghĩa.
* **Chi tiết cấu trúc**:
  * Khai báo biến `aws_region` với giá trị mặc định là `us-east-1` (bắt buộc).
  * Khai báo biến `env` (mặc định: `sandbox`).
  * Khai báo biến `sns_subscription_email` (nhận cảnh báo hạ tầng).

### Bước 4: Tạo cấu hình mẫu tham số cục bộ (`infra/environments/sandbox/terraform.tfvars.example`)
* **Lý do cần trước**: Tệp tin này đóng vai trò hướng dẫn cho người vận hành biết các giá trị cấu hình thực tế nào cần cung cấp. Việc chuẩn bị tệp tin mẫu này giúp thiết lập nhanh môi trường mà không bị nhầm lẫn về kiểu dữ liệu.
* **Chi tiết cấu trúc**:
  * Chứa mẫu khai báo cho `aws_region` (thiết lập là `us-east-1`), `env`, và `sns_subscription_email` với dữ liệu giả lập.

---

## 2. Giai Đoạn Định Hình Module Mạng (`infra/modules/networking/`)

Mạng VPC là hạ tầng xương sống. Không thể triển khai bất kỳ server ảo nào (EKS, Load Balancer, VPC Endpoints) nếu không có không gian mạng địa chỉ IP.

### Bước 5: Khai báo tham số đầu vào cho Module Mạng (`infra/modules/networking/variables.tf`)
* **Lý do cần trước**: Tệp tin này mô tả các thuộc tính cấu hình mạng (như CIDR block, danh sách subnet, availability zones, NAT Gateway). Viết file này trước giúp `main.tf` tham chiếu trực tiếp đến các biến này thay vì viết cứng giá trị (hardcode), tăng tính tái sử dụng trên nhiều môi trường.
* **Chi tiết cấu trúc**:
  * Khai báo biến `env` để phân vùng thẻ (Tagging).
  * Khai báo dải mạng `vpc_cidr` và các subnet (`public_subnet_cidrs`, `private_subnet_cidrs`).
  * Khai báo `availability_zones` mặc định trỏ về `us-east-1a`, `us-east-1b`, `us-east-1c`.
  * Khai báo cờ `enable_nat_gateway` và `single_nat_gateway` để điều khiển NAT Gateway linh hoạt theo môi trường.

### Bước 6: Khai báo tài nguyên mạng chính (`infra/modules/networking/main.tf`)
* **Lý do cần trước**: Tệp tin này chứa các định nghĩa tài nguyên mạng vật lý, tường lửa bảo mật (Security Groups) và các cổng kết nối nội bộ (VPC Endpoints). Mọi server (như worker nodes của cụm EKS, các lambda functions) đều phải được gắn vào một subnet cụ thể nằm trong mạng này và được kiểm soát bằng tường lửa tương ứng. Vì vậy, tệp tin cấu hình tài nguyên mạng chính này phải được viết ngay sau variables và trước khi deploy các dịch vụ khác.
* **Chi tiết cấu trúc**:
  * Định nghĩa `aws_vpc` và `aws_internet_gateway` để cung cấp khả năng kết nối cơ bản.
  * Phân chia `aws_subnet` public cho Load Balancer và private cho EKS nodes / Lambda.
  * Triển khai `aws_nat_gateway` (chỉ tạo 1 NAT ở sandbox để tối ưu cost).
  * Cấu hình Route Tables để kiểm soát luồng traffic mạng.
  * **Tạo các Security Groups (Task 1.3)**:
    * `sg-alb`: Cho phép traffic HTTP/HTTPS (port 80, 443) đi vào từ internet (`0.0.0.0/0`).
    * `sg-eks-nodes`: Cho phép traffic đi vào từ ALB ở các dải cổng của ứng dụng và cho phép giao tiếp nội bộ trong cụm node.
    * `sg-lambda`: Chỉ cho phép lưu lượng đi ra ngoài để đảm bảo an toàn tối đa cho các chức năng Lambda.
    * `sg-vpc-endpoints`: Cho phép cổng 443 đi vào từ EKS nodes và Lambda nodes để sử dụng tài nguyên AWS an toàn.
  * **Cấu hình VPC Endpoints (Task 1.2)**:
    * Gateway Endpoints: S3, DynamoDB.
    * Interface Endpoints: SQS, ECR API, ECR DKR, CloudWatch Logs, STS, Secrets Manager. Tất cả đều kết hợp bảo mật qua `sg-vpc-endpoints` và bật private DNS.

### Bước 7: Khai báo các đầu ra của Module Mạng (`infra/modules/networking/outputs.tf`)
* **Lý do cần trước**: Tệp tin này chứa danh sách các giá trị xuất bản ra ngoài của module mạng (VPC ID, subnet IDs, các Security Group IDs). EKS cluster và các Service Groups khác sẽ gọi và sử dụng các ID này để xác định vị trí đặt tài nguyên và áp dụng quy tắc tường lửa tương thích.
* **Chi tiết cấu trúc**:
  * Xuất `vpc_id` và các subnets.
  * Xuất các Security Group IDs: `sg_alb_id`, `sg_eks_nodes_id`, `sg_lambda_id`, `sg_vpc_endpoints_id` để các module khác (như EKS) tham chiếu.

---

## 3. Giai Đoạn Định Hình Module Lưu Trữ Dữ Liệu (`infra/modules/data-store/`)

Ứng dụng của chúng ta cần một cơ sở dữ liệu để ghi nhận trạng thái xử lý sự cố (tránh race-condition) và một bucket S3 để lưu trữ tệp bằng chứng kiểm toán (audit artifacts).

### Bước 8: Khai báo tham số đầu vào cho Module Lưu Trữ (`infra/modules/data-store/variables.tf`)
* **Lý do cần trước**: Tệp tin này định nghĩa cấu hình vòng đời của dữ liệu và các cơ chế bảo mật. Tạo file này trước giúp `main.tf` liên kết động các tham số này một cách linh hoạt theo từng môi trường.
* **Chi tiết cấu trúc**:
  * Khai báo biến `env` để định danh tài nguyên.
  * Khai báo biến `enable_s3_object_lock` (chống xóa/ghi đè bằng chứng kiểm toán).
  * Khai báo biến `s3_retention_days` để thiết lập thời gian tự động archive tệp tin.

### Bước 9: Khai báo tài nguyên lưu trữ chính (`infra/modules/data-store/main.tf`)
* **Lý do cần trước**: Tệp tin này khởi tạo database DynamoDB và S3 bucket với các cấu hình bảo mật đặc biệt như SSL/TLS Enforce Policy. Các thành phần logic xử lý sự cố (như Lambda Ingest, Integration Lambda, và CDO Correlator Worker) đều cần biết tên chính xác của các tài nguyên lưu trữ này để được cấu hình đúng quyền hạn IAM và biến môi trường.
* **Chi tiết cấu trúc**:
  * Tạo `aws_dynamodb_table` với chế độ On-Demand, cấu hình Partition Key `incident_id`.
  * Thiết lập Global Secondary Index `CorrelationAlertIndex` (với partition key `correlation_key` và sort key `alert_fingerprint`) theo đúng Task 1.6 để phục vụ truy vấn sự cố hiệu quả.
  * Cấu hình TTL tự động dọn dẹp dựa trên thuộc tính `expires_at` để tự xóa record cũ sau thời gian chỉ định.
  * Tạo `aws_s3_bucket` cho incident evidence, cấu hình chặn truy cập public, mã hóa server-side mặc định, bật versioning và lifecycle transition.
  * **Bảo mật Bucket Policy**: Định nghĩa policy loại trừ và từ chối tuyệt đối mọi yêu cầu truy xuất không an toàn (không sử dụng HTTPS - `aws:SecureTransport = false`).

### Bước 10: Khai báo các đầu ra của Module Lưu Trữ (`infra/modules/data-store/outputs.tf`)
* **Lý do cần trước**: Tệp tin này xuất các giá trị ARN và tên của DynamoDB/S3 để các module khác sử dụng. Đặc biệt, module `tenant-provision` và Integration Lambda cần các ARN này để tạo IAM policy giới hạn phạm vi truy cập dữ liệu cho từng tenant.
* **Chi tiết cấu trúc**:
  * Xuất `dynamodb_table_name` và `dynamodb_table_arn`.
  * Xuất `s3_bucket_name` và `s3_bucket_arn`.

---

## 4. Giai Đoạn Định Hình Module Giám Sát Cảnh Báo (`infra/modules/observability/`)

Hệ thống cần cung cấp các metric giám sát để kỹ sư SRE biết được trạng thái hoạt động của hàng đợi SQS, Lambda và bảng DynamoDB khi xảy ra tắc nghẽn hoặc có lỗi xảy ra.

### Bước 11: Khai báo tham số đầu vào cho Module Giám Sát (`infra/modules/observability/variables.tf`)
* **Lý do cần trước**: Tệp tin này chứa các định nghĩa cho tên hàng đợi SQS, tên bảng DynamoDB, tên S3 bucket, tên các hàm Lambda và địa chỉ email nhận thông báo cảnh báo qua SNS. Khai báo file này trước giúp module có thể liên kết động tới các tài nguyên được tạo ở các môi trường khác nhau.
* **Chi tiết cấu trúc**:
  * Khai báo các biến `sqs_queue_name`, `sqs_dlq_name` và `dynamodb_table_name` để liên kết CloudWatch Alarm.
  * Khai báo thêm `s3_bucket_name`, `ingest_lambda_name` và `integration_lambda_name` để hỗ trợ giám sát toàn bộ các dịch vụ serverless.
  * Khai báo biến `sns_subscription_email` để thiết lập kênh thông báo qua email của AWS SNS.

### Bước 12: Thiết lập tài nguyên giám sát chính (`infra/modules/observability/main.tf`)
* **Lý do cần trước**: Tệp tin này khởi tạo AWS SNS Topic và đăng ký nhận email, đồng thời thiết lập **đúng 10 CloudWatch Alarms (Task 1.10)** để theo dõi các sự cố nghiêm trọng. Đây là thành phần giám sát trung tâm của hạ tầng; viết file này giúp đảm bảo khi các tài nguyên SQS/DynamoDB/Lambda được chạy ở môi trường chính, hệ thống đo lường chất lượng dịch vụ sẽ được kích hoạt ngay lập tức.
* **Chi tiết cấu trúc**:
  * Tạo `aws_sns_topic` và `aws_sns_topic_subscription` gửi email cảnh báo tự động cho SRE.
  * **10 CloudWatch Alarms cụ thể**:
    1. `sqs_dlq_has_messages`: Cảnh báo khi có > 0 tin nhắn lỗi trong Dead Letter Queue (DLQ).
    2. `sqs_backlog`: Cảnh báo khi số lượng tin nhắn chờ trong queue chính vượt quá 100.
    3. `sqs_message_age`: Cảnh báo khi độ tuổi tin nhắn cũ nhất vượt quá 5 phút (300s).
    4. `dynamodb_read_throttled`: Cảnh báo khi xảy ra sự kiện nghẽn đọc trên DynamoDB.
    5. `dynamodb_write_throttled`: Cảnh báo khi xảy ra sự kiện nghẽn ghi trên DynamoDB.
    6. `dynamodb_throttles`: Cảnh báo chung khi tổng số ThrottledRequests trên bảng dữ liệu > 0.
    7. `lambda_ingest_errors`: Cảnh báo khi hàm Ingest Lambda bị lỗi > 5 lần trong 5 phút.
    8. `lambda_ingest_duration`: Cảnh báo khi thời gian chạy p99 của Ingest Lambda vượt quá 10 giây (10000ms).
    9. `lambda_integration_errors`: Cảnh báo khi hàm Integration Lambda bị lỗi > 5 lần trong 5 phút.
    10. `lambda_integration_duration`: Cảnh báo khi thời gian chạy p99 của Integration Lambda vượt quá 10 giây (10000ms).
    11. `s3_4xx_errors` & `s3_5xx_errors`: Cảnh báo khi số lượng lỗi 4xx/5xx trên S3 bucket chứa dữ liệu > 10 trong 5 phút.

### Bước 13: Khai báo đầu ra của Module Giám Sát (`infra/modules/observability/outputs.tf`)
* **Lý do cần trước**: Tệp tin này trả về ARN của SNS Topic cảnh báo. Nếu sau này chúng ta muốn phát triển tích hợp thêm các dịch vụ webhook bên thứ 3 (như gửi tin nhắn Slack, Jira API qua Lambda) hoặc các module phân tích sự cố AIOps cần lắng nghe SNS, họ sẽ tham chiếu trực tiếp qua output ARN này.
* **Chi tiết cấu trúc**:
  * Xuất `sns_topic_arn` để phục vụ các bên liên quan cần đăng ký nhận log alarm.

---

## 5. Giai Đoạn Định Hình Module Kubernetes EKS (`infra/modules/eks/`)

EKS là nơi lưu trữ các workload ứng dụng xử lý dữ liệu chính (Correlator Worker, AI Engine, Demo App). Nó cần chạy bên trong vùng Private subnets để đảm bảo an toàn.

### Bước 14: Khai báo tham số đầu vào cho Module EKS (`infra/modules/eks/variables.tf`)
* **Lý do cần trước**: Tệp tin này định nghĩa các tham số kết nối (VPC ID, danh sách Subnets, Security Group ID) thu nhận từ module mạng, đồng thời khai báo kích thước cụm và loại EC2 instance. Khai báo các biến này trước là điều kiện bắt buộc để cấu hình các tài nguyên EKS phức tạp ở bước sau.
* **Chi tiết cấu trúc**:
  * Khai báo liên kết hạ tầng mạng `vpc_id`, `private_subnet_ids` và `sg_eks_nodes_id`.
  * Khai báo kiểu worker node `instance_types` (mặc định: `t3.medium`).
  * Khai báo dải Auto Scaling với giá trị mặc định chuẩn hóa: `min_size = 2`, `max_size = 4`, `desired_size = 2` để đảm bảo HA tối thiểu trong cụm.

### Bước 15: Khai báo tài nguyên cụm EKS chính (`infra/modules/eks/main.tf`)
* **Lý do cần trước**: Tệp tin này triển khai cụm EKS Kubernetes Control Plane, EC2 Worker Nodes và OpenID Connect (OIDC) provider. Đây là môi trường tính toán cốt lõi. Mọi namespace của tenant, chính sách bảo mật mạng (NetworkPolicy), và Service Account của tenant (giao tiếp IRSA) chỉ có thể được tạo sau khi cụm EKS và OIDC provider hoạt động ổn định.
* **Chi tiết cấu trúc**:
  * Định nghĩa IAM Roles cho Cluster Control Plane và Node Group với các quyền truy cập mạng và container registry tối thiểu.
  * Khởi tạo EKS Cluster chạy bản Kubernetes phiên bản `1.30` ổn định, bật chế độ Private Access và kích hoạt ghi log kiểm toán (`api`, `audit`, `authenticator`) lên CloudWatch Logs để giám sát bảo mật.
  * Đính kèm Security Group của EKS Node (`sg-eks-nodes`) trực tiếp vào cấu hình `vpc_config` của cụm.
  * Triển khai EKS Managed Node Group quản lý vòng đời node và auto-scaling tự động trong private subnets.
  * Khởi tạo `aws_iam_openid_connect_provider` sử dụng thumbprint SSL của EKS để ánh xạ quyền hạn IAM Role vào Kubernetes Service Account thông qua cơ chế IRSA.

### Bước 16: Khai báo đầu ra của cụm EKS (`infra/modules/eks/outputs.tf`)
* **Lý do cần trước**: Tệp tin này xuất các biến quan trọng như cluster endpoint, cluster name và OIDC provider URL/ARN. Module `tenant-provision` sẽ lấy OIDC ARN để định cấu hình quan hệ tin cậy cho IAM role, và môi trường root sandbox cũng cần các thông số này để khởi tạo `kubernetes` provider cho các thao tác nội bộ cụm. Tệp này khép lại module EKS.
* **Chi tiết cấu trúc**:
  * Xuất tên cụm và API endpoint.
  * Xuất dữ liệu CA để client thiết lập TLS connection.
  * Xuất URL và ARN của OIDC provider để tích hợp IRSA.

---

## 6. Giai Đoạn Định Hình Module Cấp Phát Tenant (`infra/modules/tenant-provision/`)

Hạ tầng cần khả năng cô lập dữ liệu và môi trường tính toán một cách tuyệt đối cho từng khách hàng (tenant) khác nhau để đáp ứng tiêu chuẩn phi chức năng (NFR).

### Bước 17: Khai báo tham số đầu vào cho Module Tenant (`infra/modules/tenant-provision/variables.tf`)
* **Lý do cần trước**: Tệp tin này chứa định nghĩa cho ID của Tenant cần onboard, thông số ARN của các cơ sở dữ liệu dùng chung (S3/DynamoDB) và thông tin OIDC Provider thu được từ EKS. Viết tệp này trước giúp module có thể tạo ra các quyền hạn IAM scoped chính xác cho từng tenant riêng lẻ.
* **Chi tiết cấu trúc**:
  * Khai báo biến định danh `tenant_id`.
  * Nhận thông tin hạ tầng S3/DynamoDB (`s3_bucket_name`, `s3_bucket_arn`, `dynamodb_table_arn`).
  * Nhận thông số OIDC (`eks_oidc_provider_url`, `eks_oidc_provider_arn`).

### Bước 18: Triển khai các tài nguyên cô lập cho Tenant (`infra/modules/tenant-provision/main.tf`)
* **Lý do cần trước**: Tệp tin này thiết lập tường lửa mạng Kubernetes (NetworkPolicy), phân vùng chạy ảo (Namespace) và Service Account liên kết IAM Role (IRSA). Nếu không viết file này, mã nguồn ứng dụng demo của từng tenant sẽ không thể khởi chạy an toàn trên cụm EKS vì thiếu các chính sách bảo mật mạng mặc định và thiếu quyền truy cập vào vùng S3 prefix dành riêng. Đây là tệp tin bảo mật cốt lõi để triển khai kiến trúc đa người thuê (Multi-tenant isolation).
* **Chi tiết cấu trúc**:
  * Tạo `aws_iam_policy` giới hạn quyền thao tác của tenant chỉ trong prefix S3 `s3://bucket/{tenant_id}/*` và DynamoDB Table.
  * Tạo `aws_iam_role` cấu hình Trust Relationship với OIDC Provider, xác định cụ thể Service Account của tenant trong cụm EKS.
  * Tạo `kubernetes_namespace` và `kubernetes_service_account` liên kết với IAM Role trên.
  * Triển khai `kubernetes_network_policy` ở chế độ default deny ingress để cô lập lưu lượng mạng hoàn toàn giữa các tenant.

### Bước 19: Khai báo đầu ra của Module Tenant (`infra/modules/tenant-provision/outputs.tf`)
* **Lý do cần trước**: Tệp tin này xuất tên Namespace, Service Account và IAM Role ARN của tenant đó. Khi triển khai các ứng dụng thực tế (ví dụ: Demo App thu thập log cho tenant đó bằng ArgoCD Helm values), các giá trị này sẽ được tham chiếu trực tiếp để cấu hình kết nối. Tệp này hoàn thành module cô lập tenant.
* **Chi tiết cấu trúc**:
  * Xuất `tenant_namespace`.
  * Xuất `tenant_service_account_name`.
  * Xuất `tenant_iam_role_arn`.

---

## 7. Giai Đoạn Đóng Gói Mã Nguồn Lambda & Triển Khai Môi Trường Sandbox

Giai đoạn cuối cùng là hiện thực hóa các ứng dụng adapter serverless tích hợp và điều phối chính môi trường.

### Bước 20: Tạo mã nguồn Ingestion Webhook Handler (`infra/environments/sandbox/lambda/ingest.py`)
* **Lý do cần trước**: Tệp tin Python này chứa logic xử lý các HTTP webhooks được Alertmanager gửi sang. Trước khi Terraform chạy lệnh đóng gói lưu trữ và tải lên AWS Lambda, tệp mã nguồn Python này bắt buộc phải tồn tại vật lý trên đĩa. Nếu viết file `main.tf` trước mà chưa tạo file Python này, các lệnh kiểm tra và khởi tạo của Terraform sẽ bị lỗi ngay lập tức vì không tìm thấy file nguồn để đóng gói `archive_file`.
* **Chi tiết cấu trúc**:
  * Xử lý giải mã base64 và phân tích định dạng JSON của webhook payload.
  * Tách từng alert riêng lẻ trong mảng cảnh báo gửi về.
  * Tự sinh vân tay `alert_fingerprint` bằng mã hash SHA-256 để chống trùng lặp dữ liệu.
  * Định nghĩa `correlation_key` (gom nhóm theo tenant và service) để bảo toàn thứ tự sắp xếp trong hàng đợi SQS FIFO.
  * Đóng gói bản tin chuẩn hóa và gọi SDK AWS `boto3` để dispatch sang SQS.

### Bước 21: Tạo mã nguồn Integration Webhook Handler (`infra/environments/sandbox/lambda/integration.py`)
* **Lý do cần trước**: Tệp tin Python này chịu trách nhiệm gửi thông báo sang các bên thứ 3 (tạo ticket Jira và gửi tin nhắn cảnh báo Slack) khi nhận được sự cố đã được tương quan. Tương tự như tệp Ingestion, tệp này cần tồn tại trước khi Terraform biên dịch để đảm bảo gói lưu trữ Zip được đóng gói thành công mà không gây lỗi biên dịch HCL.
* **Chi tiết cấu trúc**:
  * Phân tích gói payload sự cố nhận được từ correlator worker.
  * Mô phỏng tạo khóa ticket Jira (ví dụ: `JIRA-XXXX`) tương ứng với mã incident_id.
  * Tạo cấu trúc thông báo Slack phong phú (chứa thông tin Tenant, ID incident, mức độ nghiêm trọng Severity, và link liên kết trực tiếp tới Jira).
  * Thực hiện request HTTPS POST tới URL Slack Webhook cấu hình trong biến môi trường.

### Bước 22: Phối hợp điều phối tài nguyên chính (`infra/environments/sandbox/main.tf`)
* **Lý do cần trước**: Tệp tin này đóng vai trò là "nhạc trưởng", kết nối và gọi toàn bộ 5 module con (`networking`, `data_store`, `eks`, `observability`, `tenant-provision`), đồng thời tạo ra hàng đợi đệm SQS FIFO, cả 2 Lambda Functions (Ingest và Integration) kèm theo các chính sách IAM Role scoped tương ứng. Tệp này được viết cuối cùng trong nhóm triển khai tài nguyên vật lý để đảm bảo tất cả các module con đã sẵn sàng cung cấp mã nguồn, biến số và định nghĩa giao tiếp.
* **Chi tiết cấu trúc**:
  * Triển khai cụm module nền tảng (`networking`, `data_store`, `eks`).
  * Khởi tạo **SQS FIFO Queue** và **SQS Dead Letter Queue (DLQ)** với cơ chế bảo vệ:
    * `tf1-cdo05-sandbox-alert-queue.fifo` có visibility timeout 300s, message retention 4 ngày, `content_based_deduplication = true` và chính sách redrive đẩy sang DLQ sau 3 lần thất bại (`maxReceiveCount = 3`).
    * `tf1-cdo05-sandbox-alert-dlq.fifo` giữ tin nhắn lỗi trong 14 ngày để debug và có cơ chế redrive allow policy cho phép gửi ngược lại hàng đợi chính để xử lý lại.
  * Thiết lập IAM Execution Role và IAM Policies giới hạn quyền cho 2 hàm Lambda:
    * Ingest Lambda: Chỉ có quyền `sqs:SendMessage` trên hàng đợi chính.
    * Integration Lambda: Có quyền đọc ghi DynamoDB (`GetItem`, `PutItem`, `UpdateItem`, `Query`), đọc ghi S3 bucket artifacts và lấy giá trị Secrets Manager.
  * Gọi module `observability` truyền đầy đủ tên SQS, DynamoDB, S3, và tên cả 2 Lambda functions để kích hoạt trọn vẹn 10 alarms đo lường.
  * Gọi module `tenant_a` để tự động khởi tạo hạ tầng giám sát và onboard khách hàng thử nghiệm `tenant-a` trong cụm EKS.

### Bước 23: Khai báo đầu ra của môi trường Sandbox (`infra/environments/sandbox/outputs.tf`)
* **Lý do cần trước**: Tệp tin này là bước cuối cùng trong chu trình IaC. Nó xuất ra màn hình console tất cả các endpoint kết nối sau khi Terraform chạy xong (VPC ID, EKS API Endpoint, Lambda Webhook URL, SQS URLs, DynamoDB, S3 names và các thông số Namespace/Role của Tenant A). Các kỹ sư vận hành CI/CD và nhóm phát triển AIOps sẽ sử dụng trực tiếp các đầu ra này để tích hợp hệ thống mà không cần vào AWS Web Console để tìm kiếm thủ công.
* **Chi tiết cấu trúc**:
  * Xuất endpoint API và Cluster Name của EKS.
  * Xuất Public HTTPS URL của Lambda Ingest Webhook.
  * Xuất URL của SQS Main Queue và DLQ.
  * Xuất tên S3 bucket và DynamoDB table.
  * Xuất thông số Namespace, Service Account và IAM Role của Tenant A.
