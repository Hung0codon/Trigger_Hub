# PROMPT MÔ TẢ LUỒNG SỰ KIỆN & THIẾT KẾ PIPELINE DỰ ÁN (AIOps Incident Triage Platform)

*Bạn có thể sử dụng prompt dưới đây để cung cấp ngữ cảnh đầy đủ cho LLM (Claude, GPT, Gemini) khi cần sinh mã nguồn, viết kịch bản kiểm thử, vẽ sơ đồ Sequence/Architecture, hoặc viết tài liệu chi tiết cho dự án.*

---

```text
Bạn là một Chuyên gia Kiến trúc Giải pháp Cloud (Cloud Solutions Architect) và Kỹ sư Hệ thống AIOps giàu kinh nghiệm. Hãy phân tích tài liệu thiết kế hạ tầng và quyết định kiến trúc (ADRs) dưới đây để mô tả, thiết kế chi tiết hoặc triển khai hệ thống Pipeline xử lý sự cố thông minh (AIOps Incident Triage Platform) trên AWS EKS.

---

### I. TỔNG QUAN HỆ THỐNG & ĐỊNH HƯỚNG KIẾN TRÚC
Dự án có tên là TF1 Triage Hub (CDO-05) với góc tiếp cận khác biệt: "Reliable Incident Triage Pipeline with Alert Storm Control and AI Call Gating".
Hệ thống xây dựng một mô hình siêu dữ liệu nhất quán (consistent metadata model) bao gồm: `tenant_id`, `service`, `env`, `namespace`, `deployment`, `version`, `pod` chạy xuyên suốt từ luồng runtime đến logs, metrics, alerts và lịch sử deployment nhằm cung cấp đầy đủ ngữ cảnh cho AI Engine phân tích nguyên nhân gốc rễ (RCA) theo từng khung thời gian sự cố mà không bị phân mảnh hay rò rỉ chéo dữ liệu giữa các tenant.

Các quyết định kiến trúc cốt lõi đã được thông qua (ADRs):
1. ADR-001 (Compute Target): Chọn Amazon EKS làm nền tảng tính toán cốt lõi cho mọi cấu phần (Demo workloads, Correlator Worker, AI Engine API, Observability stack) để đảm bảo tính nhất quán siêu dữ liệu tự nhiên của Kubernetes (Namespace, Labels, Service Discovery, NetworkPolicy).
2. ADR-002 (Data Storage): Chọn DynamoDB (on-demand mode) để quản lý trạng thái incident và chống trùng lặp (idempotency) nhờ ghi dữ liệu có điều kiện (conditional write) và dọn dẹp tự động qua TTL 90 ngày.
3. ADR-003 (CI/CD Strategy): GitHub Actions cho CI (build, test, security scan, push ECR) kết hợp ArgoCD cho CD (GitOps, Canary deployments, drift detection).
4. ADR-004 (Observability Stack): Chọn Prometheus Operator (Prometheus + Grafana + Alertmanager) cho metrics và Loki cho logs chạy trực tiếp trong cụm EKS để tối ưu hóa siêu dữ liệu K8s. Sử dụng Amazon CloudWatch để giám sát các dịch vụ managed của AWS (Lambda, SQS queue depth, DynamoDB metrics).
5. ADR-005 (Security Baseline): Áp dụng IAM Roles for Service Accounts (IRSA) cho pod-level AWS access control. Sử dụng Kubernetes NetworkPolicy để cô lập namespace liên tenant. Sử dụng AWS Secrets Manager làm kho chứa bí mật tập trung và đồng bộ vào cluster bằng External Secrets Operator (ESO). Bật mã hóa SSE-S3/SSE-SQS cho dữ liệu lưu trữ và truyền tải.
6. ADR-006 (Cost Trade-off): Chạy cụm EKS trên t3.medium instances (2 nodes baseline, ASG 1-3 nodes). Sử dụng DynamoDB on-demand và S3 Standard với Lifecycle Policy dọn dẹp sau 30 ngày. Cấu hình tự động scale node group về 0 vào ban đêm/cuối tuần.
7. ADR-007 (Alert Event Pipeline): Sử dụng mô hình kết hợp Ingest Lambda + SQS FIFO Queue + DynamoDB + S3 để tối đa hóa độ bền vững (durability), khử trùng lặp 2 lớp (SQS FIFO deduplication + DynamoDB idempotency) và cô lập lỗi dễ dàng qua DLQ.

---

### II. BẢN ĐỒ PHÂN CHIA VAI TRÒ & RANH GIỚI DỮ LIỆU (DATA BOUNDARIES)
Hệ thống chia tách rõ rệt thành hai luồng dữ liệu độc lập:
1. Luồng Giám sát Thông thường (Normal Observability Flow):
   - Demo App on EKS -> Prometheus (metrics) & Loki (logs) -> Grafana.
   - Bằng chứng chẩn đoán (metrics/logs thô) KHÔNG đi qua SQS. Chúng được lưu trữ ổn định tại Prometheus và Loki.
   - AI Engine hoặc SRE truy cập dữ liệu thô này qua mô hình Pull (truy vấn trực tiếp qua API Gateway/Token với quyền Read-only bị giới hạn theo tenant/service/env/time window) hoặc mô hình Push (CDO gửi bản tóm tắt định kỳ 1 phút, không stream realtime).
2. Luồng Xử lý Sự cố Cảnh báo (Alert Incident Flow):
   - PrometheusRule -> Alertmanager -> Ingest Lambda -> SQS FIFO -> CDO Correlator Worker -> DynamoDB -> AI Engine -> Jira/Slack + S3 Audit.
   - Luồng này chỉ xử lý các sự kiện cảnh báo (alert events) đóng vai trò là tác nhân kích hoạt (workflow trigger).

Phân chia trách nhiệm giữa CDO Platform và AIOps/AI Engine:
- CDO Platform sở hữu: Hạ tầng EKS (subnet riêng tư, ALB công cộng), stack giám sát (Prometheus/Loki/Alertmanager), độ tin cậy và phân phối alert (Ingest Lambda, SQS FIFO, DLQ), quản lý trạng thái và chống trùng lặp trong DynamoDB, tích hợp Jira/Slack, lưu trữ bằng chứng kiểm toán tại S3, secrets được đồng bộ từ Secrets Manager qua ESO, và thiết lập ranh giới phân quyền bảo mật (least-privilege/IRSA).
- AIOps/AI Engine sở hữu: Nhận tín hiệu kích hoạt từ CDO, chủ động truy vấn Prometheus/Loki theo khung thời gian và tenant/service được giới hạn, tổng hợp dữ liệu, tính toán baseline/anomaly, thực hiện phân tích RCA và trả về kết quả (root cause, confidence score, evidence, suggested actions).

---

### III. THIẾT KẾ PIPELINE VÀ LUỒNG SỰ KIỆN CHI TIẾT (STEP-BY-STEP)

Hãy mô tả chi tiết luồng xử lý sự kiện từ khi xảy ra lỗi ở Demo App cho tới khi tạo ticket Jira/Slack:

1. BƯỚC 1: PHÁT HIỆN SỰ CỐ & LỌC NHIỄU LỚP 1 (Alert Generation & Noise Control)
   - Lỗi phát sinh tại Demo App trên EKS sinh ra metrics/logs bất thường.
   - Prometheus scapes metrics và đánh giá định kỳ qua PrometheusRule. Nếu vi phạm ngưỡng, alert được gửi sang Alertmanager.
   - Alertmanager thực hiện lọc nhiễu tầng đầu tiên thông qua các cơ chế: Grouping (gom nhóm alert cùng thuộc tính), Inhibition (ức chế các cảnh báo phụ thuộc khi cảnh báo chính đã kích hoạt), Silence (tắt cảnh báo theo lịch hoặc bộ lọc), và thiết lập repeat_interval nhằm hạn chế spam webhook đầu vào.

2. BƯỚC 2: TIẾP NHẬN & CHUẨN HÓA CẢNH BÁO (Webhook Ingestion & Normalization)
   - Alertmanager gửi Webhook đến Ingest Lambda.
   - Ingest Lambda (nhẹ, không xử lý RCA, không gọi AI) thực hiện:
     + Xác thực schema và tính hợp lệ của payload.
     + Trích xuất và chuẩn hóa các siêu dữ liệu bắt buộc: `tenant_id`, `service`, `env`, `namespace`, `workload`, `timestamp`, `alertname`, `severity`.
     + Sinh mã khóa vân tay cảnh báo (`alert_fingerprint`) và mã khóa liên kết sự cố (`correlation_key`) dựa trên các luật định sẵn (rule-based).
     + Gửi payload đã được chuẩn hóa đến SQS FIFO Queue.

3. BƯỚC 3: XẾP HÀNG ĐỆM & KHỬ TRÙNG ĐẦU VÀO (Buffered Queueing & Deduplication)
   - SQS FIFO Queue nhận thông điệp, bảo vệ độ bền vững của cảnh báo tối đa 14 ngày kể cả khi worker phía sau bị sập.
   - SQS FIFO thực hiện khử trùng lặp lớp thứ nhất trong cửa sổ 5 phút (Deduplication Window) dựa trên `MessageDeduplicationId` sinh ra từ `alert_fingerprint`.
   - Cấu hình hàng đợi hỗ trợ High Throughput (nâng từ 300 TPS lên 3000+ TPS) để chống chịu Alert Storm (bão cảnh báo).
   - Các thông điệp bị lỗi xử lý liên tục vượt quá số lần retry tối đa sẽ được chuyển vào SQS Dead Letter Queue (DLQ) để phục vụ kiểm tra và phát lại (replay) thủ công.

4. BƯỚC 4: LIÊN KẾT SỰ CỐ & QUẢN LÝ TRẠNG THÁI (Incident Correlation & Idempotency)
   - CDO Incident Correlator Worker chạy trên EKS định kỳ poll thông điệp từ SQS FIFO.
   - Worker truy vấn DynamoDB bằng `correlation_key` để kiểm tra trạng thái:
     + NẾU TRÙNG LẶP (Duplicate Alert - cùng fingerprint): Worker cập nhật số lượng cảnh báo (`alert_count`), thời gian nhìn thấy cuối (`last_seen_at`) vào DynamoDB và dừng xử lý (bỏ qua bước gọi AI).
     + NẾU LIÊN QUAN (Related Alert - cùng correlation_key nhưng khác fingerprint): Worker cập nhật thông tin cảnh báo mới vào sự cố hiện tại trong DynamoDB, gom nhóm chúng lại và cập nhật trạng thái sự cố.
     + NẾU SỰ CỐ MỚI (New Incident): Worker tạo mới một bản ghi trạng thái trong DynamoDB (`incident_state` = `RECEIVED`) và chuyển sang bước tiếp theo.
   - Ghi dữ liệu vào DynamoDB sử dụng cơ chế conditional write (idempotency key pattern) để đảm bảo không xảy ra race condition khi có nhiều worker xử lý song song hoặc có cơ chế retry.

5. BƯỚC 5: GỌI AI ENGINE BẰNG CƠ CHẾ CỬA NGÕ (AI Call Gating & Bounded Context RCA)
   - Worker quyết định có gọi AI Engine hay không (AI Call Gating). Chỉ gọi AI khi: Tạo mới sự cố, độ nghiêm trọng tăng lên, xuất hiện alert type đặc biệt quan trọng, sự cố kéo dài quá ngưỡng, hoặc có yêu cầu phân tích lại từ con người. Bỏ qua nếu chỉ tăng số lượng alert lặp lại.
   - Khi thỏa mãn điều kiện, Worker gửi một Incident Trigger gọn nhẹ (chứa siêu dữ liệu `tenant_id`, `service`, `env`, `time_window`) sang AI Engine API.
   - AI Engine nhận trigger, sử dụng quyền truy cập Read-only giới hạn (Bounded Access) để truy vấn trực tiếp vào Prometheus (lấy metrics) và Loki (lấy logs) tương ứng với đúng tenant, service, env và khoảng thời gian xảy ra sự cố.
   - AI Engine phân tích và trả về kết quả RCA dạng JSON có cấu trúc gồm: `root_cause`, `confidence_score`, `evidence`, `missing_context`, `suggested_actions`.

6. BƯỚC 6: CẬP NHẬT TRẠNG THÁI & GHI NHẬT KÝ KIỂM TOÁN (State Update & Audit Store)
   - Worker cập nhật trạng thái sự cố trong DynamoDB sang `AI_ANALYZED`.
   - Worker ghi toàn bộ dữ liệu kiểm toán vào S3 Audit Store theo phân vùng `tenant_id/service/incident_id/`. Dữ liệu ghi bao gồm: alert payload gốc, incident trigger gửi đi, phản hồi RCA từ AI Engine, và các payload gửi Jira/Slack. S3 đảm bảo tính bền vững lâu dài (lưu giữ 30 ngày) làm bằng chứng phân tích lỗi và dữ liệu phát lại (replay/debug).

7. BƯỚC 7: TẠO TICKET VÀ THÔNG BÁO (External Integration & Delivery)
   - Worker tiến hành gọi API tích hợp bên ngoài (Secrets được đồng bộ từ Secrets Manager qua ESO):
     + Tạo/cập nhật đúng 1 ticket trên Jira (lưu lại `jira_ticket_id` vào DynamoDB). Trạng thái DynamoDB chuyển sang `JIRA_CREATED`.
     + Gửi thông tin cảnh báo kèm kết quả RCA của AI vào đúng 1 thread Slack (lưu lại `slack_thread_id`). Trạng thái DynamoDB chuyển sang `SLACK_SENT` (Hoàn thành luồng).
   - Nếu worker bị sập giữa chừng (ví dụ: tạo xong Jira nhưng chưa gửi Slack), khi SQS FIFO retry tin nhắn, Worker kiểm tra trạng thái trong DynamoDB thấy đã có `jira_ticket_id` sẽ tự động bỏ qua bước tạo Jira và thực hiện trực tiếp bước gửi Slack, đảm bảo tính idempotency tuyệt đối.

---

### IV. YÊU CẦU ĐẦU RA / THỰC THI (EXPECTED OUTPUTS)
Dựa vào luồng sự kiện và thiết kế pipeline ở trên, hãy thực hiện một trong các nhiệm vụ sau (tùy thuộc vào yêu cầu cụ thể của người dùng):
1. Thiết kế cơ sở dữ liệu: Thiết kế Schema chi tiết cho bảng DynamoDB `incident_state` và cấu trúc phân mục lưu trữ (S3 prefixes) trên S3.
2. Vẽ sơ đồ Sequence Diagram: Thể hiện chi tiết tương tác giữa EKS App, Prometheus, Alertmanager, Ingest Lambda, SQS FIFO, CDO Correlator Worker, DynamoDB, AI Engine, S3, Jira và Slack. Chỉ rõ các bước xử lý lỗi và cơ chế retry đảm bảo idempotency.
3. Sinh mã nguồn mẫu (Code/Infrastructure-as-Code):
   - Viết mã nguồn Terraform định nghĩa SQS FIFO (bao gồm Redrive Policy & DLQ), DynamoDB table, S3 bucket, và Lambda Ingest.
   - Hoặc viết mã Python/Go cho CDO Correlator Worker thực hiện poll tin nhắn từ SQS FIFO, ghi nhận trạng thái DynamoDB sử dụng conditional write, kiểm tra AI Call Gating, và tích hợp gọi AI Engine / Jira / Slack.
4. Lập kịch bản kiểm thử (Test Plan): Thiết kế các kịch bản kiểm tra khả năng phục hồi lỗi (Fault Tolerance) như: alert storm (bão cảnh báo), worker crash giữa chừng, trùng lặp cảnh báo (deduplication check), và xử lý tin nhắn độc hại (poison message) đẩy vào DLQ.
```

---
*Prompt trên đã tổng hợp đầy đủ và trực quan toàn bộ thiết kế hệ thống, các ranh giới dữ liệu và quyết định kiến trúc cốt lõi từ các tài liệu mới nhất đã được gộp.*
