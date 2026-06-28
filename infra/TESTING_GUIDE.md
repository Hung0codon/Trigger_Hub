# Hướng Dẫn Kiểm Thử Từ A Đến Z (A-Z Testing Guide)
Đầu ra này hướng dẫn chi tiết cách xác minh và kiểm thử toàn bộ hệ thống: từ luồng sự cố hạ tầng (IaC) đến quy trình tự động hóa CI/CD và GitOps.

---

## 📋 Mục Lục
1. [Chuẩn bị trước khi test](#1-chuẩn-bị-trước-khi-test)
2. [Kiểm thử luồng sự cố Webhook & Integration (A-Z)](#2-kiểm-thử-luồng-sự-cố-webhook--integration-a-z)
3. [Kiểm thử quy trình CI/CD & GitOps trên GitHub](#3-kiểm-thử-quy-trình-cicd--gitops-trên-github)
4. [Dọn dẹp tài nguyên (Tránh phát sinh chi phí)](#4-dọn-dẹp-tài-nguyên-tránh-phát-sinh-chi-phí)

---

## 1. Chuẩn Bị Trước Khi Test

### 🛠️ Yêu cầu môi trườn
* **AWS CLI**: Đã được đăng nhập với quyền Administrator của tài khoản Sandbox.
* **Trình duyệt Web**: Dùng để mở giao diện Web App Alert Simulator.
* **Git**: Dùng để đẩy nhánh code lên remote repository.

---

## 2. Kiểm Thử Luồng Sự Cố Webhook & Integration (A-Z)

Luồng kiểm thử này đi qua các thành phần:
`Simulator (Web App / Script)` ➡️ `AWS Lambda Ingest` ➡️ `Amazon SQS Queue` ➡️ `AWS Lambda Integration (Mock Mode)`

---

### 👉 Cách A: Kiểm thử qua Web App Simulator (Nếu tài khoản cho phép Public URL)

1. **Lấy URL Endpoint của Ingest Lambda**:
   Từ thư mục `infra/environments/sandbox`, chạy lệnh:
   ```powershell
   terraform output ingest_lambda_url
   ```
2. **Khởi chạy Web App**:
   * Mở tệp tin [`simulator/index.html`](../simulator/index.html) bằng trình duyệt.
   * Dán URL vào ô **Lambda Ingest Webhook URL**.
   * Chọn một mẫu sự cố bất kỳ (ví dụ: *High CPU Alert (EKS)*) và nhấn **Trigger Webhook Alert**.
   * Nếu tài khoản AWS của bạn **không chặn** Public Function URLs, bạn sẽ nhận được phản hồi **HTTP 200** thành công.

---

### 👉 Cách B: Kiểm thử qua Python Script (Nếu tài khoản chặn Public URL - Báo lỗi 403 Forbidden)

Nếu tài khoản AWS Sandbox của bạn thuộc một tổ chức có chính sách bảo mật (SCP) chặn việc public Lambda Function URLs, trình duyệt sẽ báo lỗi `Failed to fetch` hoặc `HTTP 403 Forbidden`. Lúc này, chúng ta sẽ kiểm thử bằng cách gọi trực tiếp (Direct Invoke) Lambda qua AWS SDK/Boto3:

1. **Chạy script kiểm thử bằng Python**:
   Chạy lệnh sau tại thư mục gốc của dự án:
   ```powershell
   python simulator/test_alert.py
   ```
2. **Xác nhận kết quả gửi**:
   Nếu thành công, màn hình sẽ hiển thị phản hồi thành công từ AWS Lambda:
   ```json
   HTTP Response Status Code: 200
   Response Body:
   {
     "message": "Alerts processed successfully",
     "processed": 1,
     "failed": 0,
     "errors": []
   }
   ```
3. **Kiểm tra tin nhắn trong SQS Queue**:
   Chạy lệnh sau để kiểm tra xem SQS FIFO Queue đã nhận và lưu trữ tin nhắn hay chưa:
   ```powershell
   aws sqs get-queue-attributes --queue-url https://sqs.us-east-1.amazonaws.com/945125812908/tf1-cdo05-sandbox-alert-queue.fifo --attribute-names ApproximateNumberOfMessages
   ```
   *Kết quả sẽ hiển thị `"ApproximateNumberOfMessages": "1"`, chứng minh thông điệp đã nằm an toàn trong hàng đợi.*

---


### 👉 Bước 2.4: Xác minh xử lý tích hợp (Mock Slack/Jira) trên CloudWatch
Do chúng ta chưa gán API Key thật của Jira và Slack, hệ thống sẽ chạy ở chế độ **Mock**. Ta cần kiểm tra log để đảm bảo Lambda đã phân tích và sinh thông tin tích hợp đúng đắn:

1. Đăng nhập vào **AWS Management Console**.
2. Truy cập dịch vụ **CloudWatch** $\rightarrow$ **Log groups**.
3. Chọn Log Group: `/aws/lambda/tf1-cdo05-sandbox-integration-handler`.
4. Mở Log Stream mới nhất, bạn sẽ thấy thông tin log xử lý sự cố dạng:
   ```text
   Received integration event: {"incident_id": "...", "tenant_id": "tenant-a", ...}
   Processing integration for incident <incident_id> (Tenant: tenant-a, Service: tf1-ai-triage-engine)
   Created/Updated Jira Issue: JIRA-5AE7CFD8
   Slack webhook URL not set or invalid. Skipping HTTP request. Slack Payload:
   {
     "text": "🚨 *[TF1 Triage Hub]* Incident Alert in *SANDBOX*..."
   }
   ```
*Điều này xác nhận luồng đẩy dữ liệu vào SQS và kích hoạt Lambda Integration xử lý hoàn toàn chính xác.*

---

## 3. Kiểm Thử Quy Trình CI/CD & GitOps Trên GitHub

Luồng này xác minh tính năng OIDC Trust mới tạo và khả năng tự động hóa kiểm thử mã nguồn.

### 👉 Bước 3.1: Commit và Push code lên GitHub
Nhánh code hiện tại của bạn đã được liên kết với remote `https://github.com/Hung0codon/Trigger_Hub.git`. Hãy đảm bảo tất cả file đã được đẩy lên:
```powershell
git checkout feat/docs/adr
git push origin feat/docs/adr
```

### 👉 Bước 3.2: Kiểm tra Pipeline chạy tự động (CI)
1. Truy cập vào Repository của bạn trên trình duyệt: [https://github.com/Hung0codon/Trigger_Hub/actions](https://github.com/Hung0codon/Trigger_Hub/actions).
2. Bạn sẽ thấy các bản build tương ứng với commit của mình đang chạy:
   * **`ci-terraform.yml`**: Chạy kiểm tra định dạng Terraform (`fmt`), xác thực cú pháp (`validate`) và thực hiện `terraform plan`.
   * **`ci-build-test.yml`**: Thực hiện chạy test bảo mật quét mã độc/lộ khóa (Gitleaks, Trivy).

### 👉 Bước 3.3: Tạo Pull Request (Xác minh OIDC Authentication)
1. Trên giao diện GitHub, tạo một **Pull Request (PR)** từ nhánh `feat/docs/adr` vào nhánh `main`.
2. Khi PR được tạo, GitHub Actions sẽ kích hoạt quy trình xác thực không mật khẩu (OIDC):
   * Runner của GitHub Actions sẽ yêu cầu mã xác thực Token OIDC.
   * AWS STS nhận Token, so khớp với IAM Role `tf1-cdo05-github-actions-role` (vừa tạo qua Terraform).
   * Do repository nguồn khớp chính xác với điều kiện `"repo:Hung0codon/Trigger_Hub:*"`, AWS sẽ cấp quyền tạm thời cho pipeline thực thi các thao tác đọc ghi tài nguyên.

---

## 4. Dọn Dẹp Tài Nguyên (Tránh Phát Sinh Chi Phí)

> [!CAUTION]
> Sau khi hoàn tất kiểm thử, bạn hãy dọn dẹp các tài nguyên EKS và AWS Lambda để tránh việc tài khoản Sandbox tiếp tục bị tính phí (đặc biệt là NAT Gateways và EKS cluster).

Chạy lệnh sau tại thư mục `infra/environments/sandbox`:
```powershell
terraform destroy -auto-approve
```
Đợi khoảng 10-15 phút để Terraform gỡ bỏ toàn bộ EKS, VPC, EC2 Nodes và các Lambda liên quan một cách an sau.
