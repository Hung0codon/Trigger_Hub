# 🔄 Kế Hoạch Triển Khai CI/CD Pipeline (Milestone 2)

Tài liệu này tổng hợp toàn bộ các đầu mục công việc, yêu cầu kỹ thuật và các bước kiểm tra (Definition of Done) cần thực hiện trong **Milestone 2** để xây dựng quy trình CI/CD hoàn chỉnh dựa trên mô hình GitOps (ArgoCD + Argo Rollouts) và Bảo mật chuỗi cung ứng (Trivy + Gitleaks).

---

## 🛠️ Công Việc 1: Thiết Kế Tổ Chức Kho Lưu Trữ (Repository Structure)
Phân chia cấu trúc Git thành 2 repo riêng biệt để đáp ứng tiêu chuẩn phân tách trách nhiệm (Separation of Concerns) trong GitOps.

- [ ] **Repository 1: App Repository (Mã nguồn ứng dụng & hạ tầng IaC)**
  - Thư mục `.github/workflows/` chứa các pipeline CI:
    - `ci-build-test.yml`: Chạy build, kiểm thử unit test, scan lỗi bảo mật của image và push lên AWS ECR.
    - `ci-terraform.yml`: Tự động kiểm tra cú pháp, lập kế hoạch (`plan`) và áp dụng (`apply`) hạ tầng sandbox/staging/production tùy theo nhánh.
    - `ci-image-sign.yml`: Ký số bảo mật cho Docker image.
  - Thư mục `services/` chứa source code của các service: `ingest-lambda`, `correlator-worker`, `ai-engine`, `integration-lambda`.
  - Thư mục `terraform/` chứa module IaC và cấu hình môi trường (`sandbox/`, `staging/`, `prod/`).
- [ ] **Repository 2: Config Repository (GitOps Manifests)**
  - Thư mục `argocd/` chứa file khai báo root application (`app-of-apps.yaml`) và các phân vùng dự án (`projects/`).
  - Thư mục `base/` chứa các Kustomize base manifests: namespaces, RBAC roles, deployments, services, ingress, external-secrets, network-policies.
  - Thư mục `overlays/` chứa cấu hình ghi đè tham số (Kustomize overlays) cho 3 môi trường tương ứng: `sandbox/`, `staging/`, `prod/`.
- [ ] **Cấu hình Branch Protection Rules trên GitHub**
  - Nhánh `main`: Yêu cầu Pull Request (PR) và có ít nhất 1 phê duyệt (approve) từ trưởng nhóm trước khi merge.
  - Nhánh `develop`: Yêu cầu PR để kiểm soát chất lượng code trước khi tích hợp.

---

## 🚀 Công Việc 2: Xây Dựng GitHub Actions CI Pipeline (App CI)
Viết luồng tự động kiểm thử và đóng gói ứng dụng trong file `.github/workflows/ci-build-test.yml`.

- [ ] **Quy trình các bước (Workflow Jobs)**
  1. Kích hoạt khi có commit mới hoặc mở PR trên nhánh `develop`, `main`.
  2. Xác thực với AWS qua cơ chế an toàn **GitHub OIDC to AWS IAM assume-role** (Không dùng static Access Key).
  3. Quét rò rỉ mã bí mật trong code bằng **Gitleaks**.
  4. Build Docker Image và chạy Unit Test + Integration Test của các service.
  5. Quét lỗ hổng bảo mật của Docker Image bằng **Trivy**.
  6. Ký số cho Docker Image bằng Cosign (nếu cần thiết).
  7. Đẩy (Push) image đã sạch lên AWS ECR.
  8. Ghi đè tag image mới vào **Config Repository** để kích hoạt ArgoCD tự động cập nhật.
- [ ] **Tiêu chí Đạt (Quality Gates - Pipeline sẽ FAIL nếu không đạt)**
  * **Test Pass Rate**: 100% tests phải chạy thành công.
  * **Test Coverage**: Độ bao phủ code test đạt từ 70% trở lên.
  * **Trivy Image Scan**: 0 lỗi bảo mật mức độ `CRITICAL` và `HIGH`.
  * **Gitleaks Scan**: 0 phát hiện rò rỉ secret/key trong git commit history.

---

## 🏗️ Công Việc 3: Pipeline CI/CD Cho Hạ Tầng (Terraform CI/CD)
Viết luồng kiểm soát và triển khai hạ tầng tự động trong `.github/workflows/ci-terraform.yml`.

- [ ] **Quy trình các bước (GitOps cho IaC)**
  * Khi mở PR thay đổi code Terraform:
    - Chạy `terraform fmt -check` để kiểm tra format code.
    - Chạy `terraform validate` để kiểm tra lỗi logic.
    - Chạy `terraform plan` và xuất báo cáo, tự động bình luận (post comment) kết quả plan trực tiếp lên giao diện PR của GitHub để reviewer dễ xem.
  * Khi merge PR:
    - Nhánh `feat/*`, `bugfix/*` $\rightarrow$ Tự động apply lên môi trường `sandbox`.
    - Nhánh `develop`, `release/*` $\rightarrow$ Tự động apply lên môi trường `staging`.
    - Nhánh `main` $\rightarrow$ Yêu cầu phê duyệt thủ công (Manual Action Approval) trước khi apply lên `prod`.

---

## 🔄 Công Việc 4: Cài Đặt và Cấu Hình ArgoCD (GitOps CD)
Cài đặt ArgoCD lên cụm EKS và thiết kế mô hình App-of-Apps triển khai tự động.

- [ ] **Cài đặt ArgoCD bằng Helm Chart** lên namespace `argocd`.
- [ ] **Viết File Cấu Hình Root Application (`app-of-apps.yaml`)** để quản lý đồng bộ toàn bộ các ứng dụng con.
- [ ] **Cấu hình Sync Waves (Thứ tự triển khai tuần tự)**
  - **Wave 0**: Khởi tạo hạ tầng cơ bản (Namespaces, RBAC rules, External Secrets Operator, ConfigMaps).
  - **Wave 1**: Khởi tạo nền tảng (Demo App, Services, ALB Ingress Controller, SQS/Ingest Lambda configurations).
  - **Wave 2**: Triển khai AI Engine (chạy bằng Argo Rollout Canary).
  - **Wave 3**: Triển khai CDO Correlator Worker (cần AI Engine URL).
  - **Wave 4**: Khởi chạy hệ thống giám sát (Prometheus, Loki, Grafana) và các Lambda Integration.
- [ ] **Cấu hình Kustomize Overlays**
  - Môi trường `sandbox`: replicas = 1, cấu hình resource limits tối thiểu để tiết kiệm chi phí.
  - Môi trường `staging`: replicas = 2.
  - Môi trường `prod`: Hỗ trợ Auto-scaling (HPA) từ 2 - 6 replicas, cấu hình bảo mật nghiêm ngặt.

---

## 🔒 Công Việc 5: Triển Khai Chiến Lược Release Canary Với Argo Rollouts
Triển khai kỹ thuật deploy không gián đoạn (Zero Downtime) và tự động Rollback cho AI Engine.

- [ ] **Cài đặt Argo Rollouts Controller** lên cụm EKS bằng Helm Chart.
- [ ] **Chuyển đổi Deployment thường thành Rollout Resource** cho service `tf1-ai-triage-engine`.
- [ ] **Thiết kế Tiến Trình Phân Phối Traffic (Canary Strategy)**
  * Bước 1: Chuyển 10% traffic sang phiên bản mới $\rightarrow$ Tạm dừng (Pause) vô thời hạn để SRE kiểm tra thủ công.
  * Bước 2: Chuyển lên 30% traffic $\rightarrow$ Tạm dừng 10 phút.
  * Bước 3: Chuyển lên 60% traffic $\rightarrow$ Tạm dừng 10 phút.
  * Bước 4: Hoàn tất 100% traffic lên phiên bản mới.
- [ ] **Tự Động Hóa Giám Sát Cảnh Báo (AnalysisTemplate)**
  * Tích hợp cấu hình đo lường Prometheus metrics trong khi deploy Canary.
  * Nếu tỷ lệ lỗi HTTP 5xx của version mới vượt ngưỡng 1% hoặc Lambda báo lỗi trong vòng 5 phút $\rightarrow$ Hủy bỏ tiến trình (Abort Rollout) và tự động Rollback toàn bộ traffic về phiên bản cũ an toàn.
