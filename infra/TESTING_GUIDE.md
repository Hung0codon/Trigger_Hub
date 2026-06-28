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

### 🛠️ Yêu cầu môi trường
* **AWS CLI**: Đã được đăng nhập với quyền Administrator của tài khoản Sandbox.
* **Trình duyệt Web**: Dùng để mở giao diện Web App Alert Simulator.
* **Git**: Dùng để đẩy nhánh code lên remote repository.

---

## 2. Kiểm Thử Luồng Sự Cố Webhook & Integration (A-Z)

Luồng kiểm thử này đi qua các thành phần:
`Simulator Web App` ➡️ `AWS Lambda Ingest` ➡️ `Amazon SQS Queue` ➡️ `AWS Lambda Integration (Mock Mode)` ➡️ `CloudWatch Logs`

### 👉 Bước 2.1: Lấy URL Endpoint của Ingest Lambda
Từ thư mục `infra/environments/sandbox`, chạy lệnh sau để kiểm tra đầu ra:
```powershell
terraform output ingest_lambda_url
```
*Kết quả mẫu:* `"https://x2ybvssszftteooo43acita4jq0iyllt.lambda-url.us-east-1.on.aws/"`

### 👉 Bước 2.2: Khởi chạy và cấu hình Web App Simulator
1. Mở tệp tin [`simulator/index.html`](../simulator/index.html) bằng trình duyệt (Double-click vào file).
2. Dán địa chỉ URL thu được ở **Bước 2.1** vào ô **Lambda Ingest Webhook URL**.
3. Tại ô **Load Incident Template**, chọn một mẫu sự cố bất kỳ (ví dụ: *High CPU Alert (EKS)* hoặc *DynamoDB Read Throttling*). 
4. Hệ thống sẽ tự động hiển thị mẫu Payload JSON tương thích ở khung bên phải.

### 👉 Bước 2.3: Kích hoạt sự cố giả lập
1. Nhấn nút **Trigger Webhook Alert**.
2. **Quan sát phản hồi**:
   * Nếu thành công: Ô kết quả hiển thị màu xanh lá **Success! (HTTP 200)** kèm thông tin:
     ```json
     {"message": "Alert ingested successfully", "incident_id": "..."}
     ```
   * Sơ đồ luồng (Pipeline Visualization) trên web sẽ nhấp nháy đèn báo hiệu tín hiệu truyền tải.

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
