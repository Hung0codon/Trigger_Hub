# Hướng Dẫn Kiểm Thử Hệ Thống Từ A Đến Z (A-Z Testing & Verification Guide)

Tài liệu này hướng dẫn chi tiết cách kiểm thử và xác minh toàn bộ luồng xử lý sự cố của hệ thống **Triage Hub** trên môi trường AWS Sandbox, bao gồm cả phương án bypass khi tài khoản bị khóa bởi chính sách bảo mật SCP (HTTP 403 Forbidden).

---

## 📋 Mục Lục
1. [Chuẩn bị môi trường trước khi kiểm thử](#1-chuẩn-bị-môi-trường-trước-kiểm-thử)
2. [Giai đoạn 1: Kiểm thử luồng Ingestion (Ingest Lambda ➡️ SQS Queue)](#2-giai-đoạn-1-kiểm-thử-luồng-ingestion-ingest-lambda-➡️-sqs-queue)
3. [Giai đoạn 2: Kiểm thử luồng Integration (Integration Lambda ➡️ Mock Slack/Jira)](#3-giai-đoạn-2-kiểm-thử-luồng-integration-integration-lambda-➡️-mock-slackjira)
4. [Giai đoạn 3: Xác minh tự động hóa CI/CD & OIDC Trust trên GitHub](#4-giai-đoạn-3-xác-minh-tự-động-hóa-cicd--oidc-trust-trên-github)
5. [Dọn dẹp tài nguyên (Tránh phát sinh chi phí)](#5-dọn-dẹp-tài-nguyên-tránh-phát-sinh-chi-phí)

---

## 1. Chuẩn Bị Môi Trường Trước Khi Kiểm Thử

Để thực hiện kiểm thử thành công, máy cá nhân của bạn cần chuẩn bị:
* **AWS CLI**: Đã đăng nhập tài khoản AWS Sandbox của bạn và cấu hình Region mặc định là `us-east-1`.
  * *Lệnh kiểm tra:* `aws sts get-caller-identity` (Xác nhận trả về thông tin tài khoản của bạn).
* **Python 3.x & Boto3**: Dùng để chạy các scripts giả lập cuộc gọi an toàn tới AWS.
  * *Lệnh cài đặt thư viện:* `pip install boto3`
* **Trình duyệt Web**: Dùng để mở giao diện kiểm thử tương tác Web Simulator.

---

## 2. Giai Đoạn 1: Kiểm Thử Luồng Ingestion (Ingest Lambda ➡️ SQS Queue)

Luồng kiểm thử này xác minh khả năng tiếp nhận Alert từ Prometheus, chuyển đổi cấu trúc JSON và đẩy thông điệp vào hàng đợi tin nhắn SQS FIFO.

### 👉 Cách A: Kiểm thử qua HTTP Web Simulator (Chỉ dùng nếu tài khoản cho phép Public URL)
1. **Lấy URL Endpoint của Ingest Lambda**:
   Tại thư mục `infra/environments/sandbox/`, chạy lệnh:
   ```powershell
   terraform output ingest_lambda_url
   ```
   *Kết quả mẫu:* `https://xxxx.lambda-url.us-east-1.on.aws/`
2. **Thực hiện gửi Alert**:
   * Mở tệp tin [**`simulator/index.html`**](../simulator/index.html) bằng trình duyệt.
   * Dán URL vừa lấy vào ô **Lambda Ingest Webhook URL**.
   * Chọn mẫu sự cố (ví dụ: *High CPU Alert*) và nhấn **Trigger Webhook Alert**.
   * *Nếu thành công:* Kết quả trả về màu xanh lá **Success! (HTTP 200)**.
   * *Nếu thất bại (Báo lỗi 403 Forbidden hoặc Failed to Fetch):* Vui lòng chuyển sang **Cách B** (do tài khoản AWS bị chặn chính sách Public URL).

### 👉 Cách B: Kiểm thử qua Giao diện Web + Python Command Bypass (Khuyên dùng cho Sandbox)
1. Mở tệp tin [**`simulator/index.html`**](../simulator/index.html) trên trình duyệt.
2. Tùy chỉnh các thông số sự cố trên form (như Tenant ID, Service, Severity, Alert Name...).
3. Xuống mục **AWS SCP 403 / Network Connection Fallback** ngay phía dưới nút bấm, nhấn nút **Copy** để sao chép câu lệnh Python được sinh tự động theo dữ liệu bạn vừa chỉnh sửa.
4. Mở PowerShell trên máy tính của bạn, dán (Paste) câu lệnh vào và nhấn **Enter**.
5. *Kết quả:* Lệnh chạy thành công và trả về thông tin Lambda đã nhận xử lý:
   ```json
   HTTP Response Status Code: 200
   Response Body:
   {
     "message": "Alerts processed successfully",
     "processed": 1
   }
   ```

### 👉 Cách C: Chạy trực tiếp Script file
Chạy file script Python đã được dựng sẵn từ thư mục gốc của dự án:
```powershell
python simulator/test_alert.py
```

### 🔍 Xác minh dữ liệu trong SQS FIFO Queue
Sau khi kích hoạt sự cố ở một trong các bước trên, hãy chạy lệnh sau để kiểm tra xem tin nhắn đã được chuyển tiếp vào hàng đợi SQS hay chưa:
```powershell
aws sqs get-queue-attributes --queue-url https://sqs.us-east-1.amazonaws.com/945125812908/tf1-cdo05-sandbox-alert-queue.fifo --attribute-names ApproximateNumberOfMessages
```
*Xác nhận:* Kết quả trả về `"ApproximateNumberOfMessages": "1"` (hoặc số lớn hơn 0). Điều này chứng minh luồng Ingestion hoạt động hoàn toàn chính xác.

---

## 3. Giai Đoạn 2: Kiểm Thử Luồng Integration (Integration Lambda ➡️ Mock Slack/Jira)

Luồng kiểm thử này xác minh khả năng đọc thông điệp sự cố, phân tích cấu trúc sự cố để tự động tạo vé sự cố Jira và gửi cảnh báo dạng Markdown tới Slack.

Do EKS Cluster và ArgoCD chưa chạy worker kéo tin từ SQS để xử lý tự động, chúng ta sẽ thực hiện **kích hoạt trực tiếp (Direct Invoke)** hàm Integration Lambda bằng một payload mẫu để kiểm tra kết quả ghi nhận log:

### 👉 Bước 3.1: Gọi hàm Integration Lambda trực tiếp bằng AWS CLI
Chạy lệnh sau trên terminal để gửi một payload sự cố mô phỏng từ SQS trực tiếp vào hàm Integration Lambda:
```powershell
aws lambda invoke --function-name tf1-cdo05-sandbox-integration-handler --payload "{\`"incident_id\`": \`"inc-999-eks-failure\`", \`"tenant_id\`": \`"tenant-a\`", \`"service\`": \`"tf1-ai-triage-engine\`", \`"alertname\`": \`"CPUThresholdExceeded\`", \`"severity\`": \`"critical\`", \`"summary\`": \`"EKS CPU is critical on sandbox node\`", \`"description\`": \`"Node cpu utilization is at 96%\`", \`"rca_report\`": \`"Pod memory leaks detected inside EKS node\`r\`nCandidate for pod restart\`"}" --cli-binary-format raw-in-base64-out output_integration.json
```
*Xác nhận:* Lệnh trả về kết quả `"StatusCode": 200`.

### 👉 Bước 3.2: Xác minh Log thông báo tích hợp Slack/Jira trên CloudWatch
Chúng ta sẽ kiểm tra log của Integration Lambda xem hệ thống đã tạo Jira Ticket và chuẩn bị nội dung tin nhắn Slack giả lập hay chưa:

1. Chạy lệnh sau để liệt kê các log streams của Integration Lambda:
   ```powershell
   aws logs describe-log-streams --log-group-name /aws/lambda/tf1-cdo05-sandbox-integration-handler --order-by LastEventTime --descending --max-items 1
   ```
   *Lấy giá trị `logStreamName` từ kết quả trả về.*

2. Chạy lệnh sau để xem nội dung log chi tiết (thay thế `<LOG_STREAM_NAME>` bằng giá trị vừa copy được):
   ```powershell
   aws logs get-log-events --log-group-name /aws/lambda/tf1-cdo05-sandbox-integration-handler --log-stream-name "<LOG_STREAM_NAME>" --query "events[].message"
   ```
   *Xác nhận log ghi nhận tương tự:*
   ```text
   "Processing integration for incident inc-999-eks-failure (Tenant: tenant-a, Service: tf1-ai-triage-engine)"
   "Created/Updated Jira Issue: JIRA-INC-999-"
   "Slack webhook URL not set or invalid. Skipping HTTP request. Slack Payload:"
   "{ \"text\": \"🚨 *[TF1 Triage Hub]* Incident Alert in *SANDBOX*...\" }"
   ```

---

## 4. Giai Đoạn 3: Xác Minh Tự Động Hóa CI/CD & OIDC Trust Trên GitHub

Giai đoạn này giúp bạn kiểm tra xem mã nguồn dự án của bạn khi đẩy lên GitHub có tự động kích hoạt các pipeline kiểm tra mã và xác thực an toàn với tài khoản AWS của bạn hay không.

### 👉 Bước 4.1: Đẩy toàn bộ thay đổi lên Git
Hãy đảm bảo bạn đang ở đúng nhánh và thực hiện đẩy (push) code mới nhất lên remote:
```powershell
git checkout feat/docs/adr
git push origin feat/docs/adr
```

### 👉 Bước 4.2: Giám sát GitHub Actions chạy tự động (CI)
1. Mở trình duyệt và truy cập trang GitHub Actions của bạn: [https://github.com/Hung0codon/Trigger_Hub/actions](https://github.com/Hung0codon/Trigger_Hub/actions).
2. Kiểm tra xem các Workflow sau có khởi chạy thành công (hiển thị màu xanh lá) hay không:
   * **`ci-terraform.yml`**: Kiểm tra mã Terraform định dạng (`fmt`), cú pháp (`validate`) và chạy thử nghiệm kế hoạch (`plan`).
   * **`ci-build-test.yml`**: Quét quét mã nguồn tìm lỗ hổng bảo mật và lộ khóa API (Trivy & Gitleaks).

### 👉 Bước 4.3: Xác minh OIDC Trust (Kết nối không mật khẩu AWS)
1. Trên kho mã nguồn GitHub, tạo một **Pull Request (PR)** từ nhánh `feat/docs/adr` vào nhánh `main`.
2. Theo dõi pipeline chạy trong PR.
3. Nhờ cấu hình hạ tầng OIDC trong [**`github_oidc.tf`**](github_oidc.tf), GitHub Runner sẽ tự động xác thực trực tiếp với AWS IAM Role `tf1-cdo05-github-actions-role` thông qua OIDC Token mà không cần cấu hình Access Key hay Secret Key thủ công, đảm bảo an toàn tuyệt đối.

---

## 5. Dọn Dẹp Tài Nguyên (Tránh Phát Sinh Chi Phí)

> [!CAUTION]
> Sau khi đã kiểm thử và xác nhận các luồng nghiệp vụ hoạt động trơn tru, bạn hãy dọn dẹp hạ tầng Sandbox ngay lập tức để tránh phát sinh chi phí ngoài ý muốn từ các dịch vụ AWS luôn hoạt động (đặc biệt là NAT Gateways và EKS cluster).

Chạy lệnh sau tại thư mục `infra/environments/sandbox/`:
```powershell
terraform destroy -auto-approve
```
*Thời gian dọn dẹp sẽ mất khoảng 10-15 phút để gỡ bỏ toàn bộ cụm máy ảo EC2 Nodes, EKS, Load Balancer, VPC và các tài nguyên Lambda.*
