# 🔄 Nhật Ký Triển Khai CI/CD Pipeline - Bước Theo Bước

Tài liệu này ghi lại chi tiết quá trình xây dựng các luồng tích hợp và triển khai tự động (CI/CD) trong dự án **Triage Hub**, kèm theo giải thích cặn kẽ tại sao mỗi tệp được tạo, cấu trúc của nó, và ý nghĩa của từng dòng lệnh để bạn có thể nắm bắt và hiểu rõ tường tận hệ thống mình đang vận hành.

---

## 1. Pipeline Triển Khai Hạ Tầng IaC (`.github/workflows/ci-terraform.yml`)

### 🔍 Tại sao cần tệp tin này?
Trong một dự án thực tế, hạ tầng không bao giờ được cấu hình thủ công bằng cách chạy lệnh `terraform apply` trực tiếp dưới máy local của kỹ sư. Điều này gây ra các rủi ro cực kỳ lớn:
1. **Mất kiểm soát phiên bản**: Không biết ai đã thay đổi gì trên cloud, tại sao lại thay đổi.
2. **Xung đột trạng thái (State drift/lock)**: Hai kỹ sư cùng apply một lúc có thể làm hỏng tệp tin trạng thái (`terraform.tfstate`).
3. **Lỗi bảo mật**: Máy local của kỹ sư có thể chứa mã độc hoặc bị lộ quyền Administrator của AWS.

Tệp tin `.github/workflows/ci-terraform.yml` sinh ra để biến toàn bộ quá trình thay đổi hạ tầng thành một quy trình chuẩn hóa: **Code thay đổi hạ tầng $\rightarrow$ Mở PR duyệt $\rightarrow$ Tự động Test & Plan $\rightarrow$ Phê duyệt $\rightarrow$ Tự động Apply trên Cloud từ GitHub Actions**.

---

### 🛠️ Giải thích chi tiết cấu trúc dòng lệnh của `ci-terraform.yml`

#### A. Trigger (Bộ kích hoạt pipeline)
```yaml
on:
  pull_request:
    branches: [main, develop]
    paths: ["infra/**"]
  push:
    branches: [main, develop]
    paths: ["infra/**"]
```
* **Ý nghĩa**: Pipeline chỉ kích hoạt khi có sự thay đổi (commit mới hoặc mở Pull Request) tác động vào các file nằm trong thư mục `infra/**`. Nếu bạn chỉ sửa file tài liệu `.md` ở ngoài, pipeline sẽ **không chạy vô ích**, giúp tiết kiệm thời gian và tài nguyên CI.

#### B. Phân quyền bảo mật (Permissions)
```yaml
permissions:
  id-token: write      # Cực kỳ quan trọng: Cho phép GitHub yêu cầu mã bảo mật OIDC từ AWS STS.
  contents: read       # Cho phép checkout đọc mã nguồn.
  pull-requests: write # Cho phép GitHub Actions tự viết nhận xét (plan output) vào PR.
```

#### C. Quy trình kiểm tra (Jobs)

##### Job 1: `validate` (Kiểm tra cú pháp & tính nhất quán)
```yaml
      - name: Terraform Format Check
        run: terraform fmt -check -recursive
```
* **Tại sao cần**: Đảm bảo tất cả code viết ra đều tuân theo chuẩn format của HashiCorp. Nếu viết code cẩu thả (thụt lề sai, thừa dấu cách), bước này sẽ báo lỗi (FAIL) lập tức.
```yaml
      - name: Terraform Validate
        run: |
          cd environments/sandbox
          terraform validate
```
* **Tại sao cần**: Kiểm tra xem các biến khai báo có đúng kiểu dữ liệu không, có tài nguyên nào tham chiếu sai ID không mà không cần kết nối với AWS.

##### Job 2: `plan` (Chạy thử nghiệm và báo cáo)
```yaml
      - name: Configure AWS Credentials (OIDC)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::945125812908:role/tf1-cdo05-github-actions-role
          aws-region: us-east-1
          audience: sts.amazonaws.com
```
* **Sự thay đổi mang tính đột phá về bảo mật (OIDC - OpenID Connect)**: 
  > [!IMPORTANT]
  > Thay vì lưu trữ Access Key và Secret Key của AWS một cách thủ công trên GitHub Secrets (có nguy cơ bị hack, lộ lọt, không tự đổi key), chúng ta dùng **OIDC**. 
  > GitHub Actions sẽ tự sinh ra một Token bảo mật ngắn hạn dạng Web Token, gửi lên AWS STS để xác thực "Tôi là GitHub đại diện cho repo này". AWS xác thực đúng sẽ cấp cho GitHub một quyền truy cập tạm thời chỉ có hiệu lực trong vòng **15 phút**. Hết 15 phút, quyền này tự hủy.
```yaml
      - name: Post Plan to PR
        uses: actions/github-script@v7
```
* **Tại sao cần**: Tự động lấy kết quả `terraform plan` và gửi bình luận trực tiếp vào cuộc trò chuyện Pull Request. Người duyệt (Reviewer) chỉ cần mở PR ra là thấy hạ tầng sắp thêm/sửa/xóa những gì để click duyệt merge, cực kỳ trực quan.

##### Job 3: `apply` (Triển khai thực tế)
```yaml
    if: github.event_name == 'push'
```
* **Tại sao cần**: Chỉ chạy khi code đã được kiểm tra thành công và được MERGE chính thức vào nhánh `develop` hoặc `main` (sự kiện push). Khi đó hạ tầng thật trên AWS mới thực sự thay đổi.

---
---

## 2. Pipeline Tích Hợp Ứng Dụng & Quét Bảo Mật (`.github/workflows/ci-build-test.yml`)

### 🔍 Tại sao cần tệp tin này?
Khi viết các ứng dụng Backend (như AI Engine hay Ingest Lambda), việc chuyển giao code lên container gặp rất nhiều rủi ro:
1. **Lộ lọt mật khẩu/token**: Code chứa key AWS hoặc password database bị push lên Github.
2. **Lỗi logic ứng dụng**: Code mới làm hỏng tính năng cũ.
3. **Lỗ hổng bảo mật thư viện (CVE)**: Sử dụng các thư viện Python/Node cũ chứa mã độc hoặc bị hacker khai thác.

Tệp tin `ci-build-test.yml` xây dựng một **Quality Gate (Cổng kiểm soát chất lượng)** nghiêm ngặt. Bất kỳ dòng code nào muốn đóng gói thành Docker Image và deploy lên Kubernetes đều phải vượt qua bài kiểm tra bảo mật này.

---

### 🛠️ Giải thích chi tiết cấu trúc dòng lệnh của `ci-build-test.yml`

#### A. Quét mã bí mật (Job `security-scan`)
```yaml
      - name: Gitleaks Secret Scanner
        uses: gitleaks/gitleaks-action@v2
```
* **Tại sao cần**: `Gitleaks` là công cụ quét bảo mật hàng đầu. Nó sẽ phân tích toàn bộ lịch sử commit trong quá khứ và hiện tại để tìm xem có chuỗi ký tự nào giống AWS Access Key, Slack Webhook URL, Private Key, hay Database Password hay không. Nếu phát hiện thấy, nó lập tức khóa pipeline lại không cho build tiếp để ngăn chặn thảm họa rò rỉ thông tin bảo mật.

#### B. Chạy Test & Ràng buộc tỷ lệ bao phủ (Job `build-and-test`)
```yaml
      - name: Run Unit Tests with Coverage Gate
        run: |
          # pytest --cov=services/ --cov-fail-under=70
```
* **Tại sao cần**: Yêu cầu chạy toàn bộ các file test để kiểm tra logic code. Đồng thời, cấu hình `--cov-fail-under=70` bắt buộc các lập trình viên phải viết code test bao phủ ít nhất **70% số dòng code logic**. Nếu viết code mới mà lười viết test, độ bao phủ giảm xuống dưới 70%, pipeline sẽ báo lỗi (FAIL) và từ chối deploy.

#### C. Quét lỗ hổng của Container Image bằng Trivy
```yaml
      - name: Trivy CVE Scanner
        uses: aquasecurity/trivy-action@master
        with:
          input: /tmp/image.tar
          severity: 'HIGH,CRITICAL'
          exit-code: '1'
```
* **Tại sao cần**: `Trivy` quét toàn bộ hệ điều hành nền (Base OS như Alpine, Ubuntu) và các thư viện bên trong Docker image để tìm kiếm các lỗi CVE (Common Vulnerabilities and Exposures).
* **Cấu hình exit-code: '1'**: Cực kỳ nghiêm ngặt. Nếu Trivy phát hiện bất kỳ lỗ hổng nào thuộc mức độ nguy hiểm cao (`HIGH` hoặc `CRITICAL`), nó sẽ trả về mã lỗi 1 khiến build bị đóng băng. Ứng dụng lỗi thời hoặc không an toàn sẽ **không bao giờ** lọt được lên cụm Kubernetes.

#### D. GitOps Promotion (Đẩy cấu hình ứng dụng mới lên GitOps)
```yaml
      - name: Update Kubernetes Manifest Image Tag
        run: |
          cd manifests/overlays/sandbox
          # kustomize edit set image tf1-ai-engine=...
```
* **Tại sao cần**: Đây chính là trái tim của GitOps. 
  * CI pipeline **không tự chạy lệnh `kubectl apply`** để thay đổi pod trên Kubernetes. 
  * Thay vào đó, sau khi build image sạch thành công và đẩy lên AWS ECR, nó tự động cập nhật (commit) thẻ tag của image mới đó vào thư mục manifest (`manifests/overlays/sandbox`) trên Git.
  * ArgoCD chạy trong EKS sẽ nhận thấy Git thay đổi và tự động kéo image mới về triển khai lên cụm. Điều này đảm bảo Git luôn là nguồn thông tin chân lý duy nhất (Single Source of Truth) quản lý mọi thứ trên Cluster.

---
---

## 3. Cấu Hình Đồng Bộ ArgoCD Root Application (`manifests/argocd/app-of-apps.yaml`)

### 🔍 Tại sao cần tệp tin này?
Khi sử dụng ArgoCD để triển khai ứng dụng Kubernetes, nếu dự án có hàng chục microservices, việc khai báo thủ công từng Application trên giao diện UI của ArgoCD sẽ gây ra:
1. **Thiếu tính tự động hóa**: Khi thêm mới một service, ta phải vào giao diện web cấu hình tay.
2. **Khó phục hồi**: Khi cụm EKS bị hỏng (disaster recovery), ta phải cấu hình lại tay toàn bộ danh sách app từ đầu.

Mô hình **App-of-Apps (Ứng dụng của các Ứng dụng)** giải quyết triệt để vấn đề này. 
* Ta chỉ cần tạo **một ứng dụng gốc duy nhất (Root Application)** có tên `tf1-root`.
* Root App này trỏ đến thư mục chứa các tệp manifest của các ứng dụng con (`manifests/argocd/apps`).
* Khi có bất kỳ ứng dụng con nào được thêm mới vào thư mục đó trên Git, ArgoCD sẽ tự động phát hiện và triển khai (deploy) ứng dụng con đó lên cụm Kubernetes mà không cần con người thao tác trên UI.

---

### 🛠️ Giải thích chi tiết cấu trúc dòng lệnh của `app-of-apps.yaml`

#### A. Khai báo Tài nguyên ArgoCD Application
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: tf1-root
  namespace: argocd
```
* **Ý nghĩa**: Khai báo một đối tượng Custom Resource Definition (CRD) của ArgoCD. Nó nằm trong namespace `argocd` để bộ điều khiển ArgoCD Controller có thể nhận biết và quản lý.

#### B. Cơ chế Tự Dọn Dẹp (Finalizers)
```yaml
  finalizers:
    - resources-finalizer.argocd.argoproj.io
```
* **Tại sao cần**: Đây là cơ chế bảo vệ an toàn. Khi bạn xóa tệp `app-of-apps.yaml` này, ArgoCD sẽ tự động kích hoạt quá trình dọn dẹp (cascade delete) xóa toàn bộ các ứng dụng con và các tài nguyên Kubernetes liên quan trong cụm để tránh bị "rác hạ tầng" (dangling resources).

#### C. Cấu hình Nguồn đồng bộ (Source)
```yaml
spec:
  project: default
  source:
    repoURL: https://github.com/me-dangnhatminh/xbrain-capstone-cdo5.git
    targetRevision: HEAD
    path: manifests/argocd/apps
```
* **Ý nghĩa**:
  * `repoURL`: Chỉ định địa chỉ kho lưu trữ Git chứa toàn bộ mã nguồn manifests.
  * `targetRevision`: Luôn bám sát nhánh mới nhất (`HEAD`) của Git.
  * `path`: Chỉ định thư mục chứa danh sách các ứng dụng con cần quét. Ở đây là thư mục `manifests/argocd/apps`.

#### D. Điểm đến & Chính sách Tự động Đồng bộ (Destination & Sync Policy)
```yaml
  destination:
    server: https://kubernetes.default.svc
```
* **Ý nghĩa**: Deploy trực tiếp vào cụm Kubernetes nội bộ nơi ArgoCD đang chạy (`kubernetes.default.svc`).
```yaml
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```
* **Ý nghĩa của các tham số tự đồng bộ**:
  * **`prune: true`**: Nếu một file manifest bị xóa khỏi Git, ArgoCD sẽ lập tức ra lệnh xóa tài nguyên tương ứng trên cụm Kubernetes.
  * **`selfHeal: true`**: Nếu một kỹ sư vô tình dùng lệnh `kubectl edit` hoặc `kubectl delete` để sửa tay tài nguyên trên cụm (gây ra hiện tượng lệch cấu hình - configuration drift), ArgoCD sẽ tự động phát hiện sự khác biệt và nạp đè cấu hình từ Git về cụm để sửa lỗi (Self-Healing).

---
---

## 4. Khởi Tạo Ứng Dụng Con Cho Cấu Hình Nền (`manifests/argocd/apps/namespaces-rbac.yaml`)

### 🔍 Tại sao cần tệp tin này?
Trong Kubernetes, các ứng dụng không thể được cài đặt một cách hỗn loạn trong cùng một phân vùng. Ta cần tạo các **Namespace** (không gian tên) riêng biệt để cô lập tài nguyên và gán các chính sách **RBAC** (Role-Based Access Control) để giới hạn quyền hạn.

Tuy nhiên, các Namespace và RBAC rules phải **luôn luôn tồn tại trước** khi các Service (như platform-service hay ai-engine) được khởi chạy. Nếu cố tình deploy Service trước khi Namespace của nó được tạo, Kubernetes sẽ báo lỗi `Namespace not found` và dừng quá trình cài đặt.

Tệp tin `namespaces-rbac.yaml` được cấu hình với **Sync Wave: "0"** để giải quyết vấn đề thứ tự này.

---

### 🛠️ Giải thích chi tiết cấu trúc dòng lệnh của `namespaces-rbac.yaml`

#### A. Thuộc tính Sync Wave (Sóng đồng bộ)
```yaml
  annotations:
    argocd.argoproj.io/sync-wave: "0"
```
* **Tại sao cần**: Đây là chìa khóa điều khiển thứ tự triển khai trong ArgoCD. 
  * ArgoCD sẽ đọc tất cả các file Application con và phân nhóm chúng theo chỉ số `sync-wave` (từ thấp đến cao).
  * Nhóm có wave `0` (nhỏ nhất) sẽ được đồng bộ và cài đặt trước. 
  * Chỉ khi toàn bộ các tài nguyên trong wave `0` ở trạng thái **Healthy (Khỏe mạnh)**, ArgoCD mới tiếp tục chuyển sang triển khai wave `1` (`platform-service`).

#### B. Đường dẫn nguồn (Source Path)
```yaml
  source:
    repoURL: https://github.com/me-dangnhatminh/xbrain-capstone-cdo5.git
    targetRevision: HEAD
    path: manifests/overlays/sandbox/namespaces-rbac
```
* **Ý nghĩa**: Trỏ trực tiếp đến thư mục overlay của sandbox dành riêng cho tài nguyên nền (`namespaces-rbac`). Điều này cho phép ta tùy chỉnh linh hoạt các phân quyền RBAC khác nhau giữa sandbox (nhiều quyền cho dev test) và production (quyền hạn cực kỳ thắt chặt).

---
---

## 5. Khởi Tạo Ứng Dụng Con Cho Dịch Vụ Nền Tảng (`manifests/argocd/apps/platform-service.yaml`)

### 🔍 Tại sao cần tệp tin này?
Dịch vụ nền tảng (**Platform Service**) chứa các Deployment, Service và ALB Ingress để tiếp nhận cảnh báo từ Alertmanager đi vào, đóng vai trò như cổng tiếp nhận trung gian (Ingest Gateway).

Do đó, nó cần được khởi chạy ngay sau khi phân vùng mạng (Namespaces) và phân quyền bảo mật (RBAC) đã sẵn sàng. Tệp tin này được gán cấu hình **Sync Wave: "1"** để đảm bảo nó được deploy sau wave `0`. Việc tách ứng dụng này giúp SRE dễ dàng quản lý và nâng cấp cổng tiếp nhận độc lập mà không làm gián đoạn AI Engine xử lý phân tích ở phía sau.

---

### 🛠️ Giải thích chi tiết cấu trúc dòng lệnh của `platform-service.yaml`

#### A. Thuộc tính Sync Wave (Sóng đồng bộ)
```yaml
  annotations:
    argocd.argoproj.io/sync-wave: "1"
```
* **Tại sao cần**: Đảm bảo ArgoCD chỉ khởi động quá trình tải file manifests của ứng dụng này sau khi wave `0` (`namespaces-rbac`) chuyển sang trạng thái xanh (Healthy).

#### B. Địa chỉ Namespace đích (Destination Namespace)
```yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: tf1-cdo05-sandbox-platform
```
* **Ý nghĩa**: Định rõ vị trí triển khai. Ứng dụng này sẽ nằm trọn trong namespace cô lập `tf1-cdo05-sandbox-platform` nhằm hạn chế tối đa nguy cơ lây lan sự cố giữa các thành phần khác nhau của hệ thống.

---
---

## 6. Khởi Tạo Ứng Dụng Con Cho Động Cơ Trí Tuệ Nhân Tạo AI Engine (`manifests/argocd/apps/ai-engine.yaml`)

### 🔍 Tại sao cần tệp tin này?
**AI Engine** (`tf1-ai-triage-engine`) là trái tim phân tích thông minh của hệ thống. Nó chịu trách nhiệm chính trong việc nhận dữ liệu cảnh báo từ hàng đợi, phân loại độ ưu tiên, chỉ định phòng ban xử lý và gợi ý tài liệu khắc phục (Playbook).

Bởi vì AI Engine phụ thuộc vào cơ sở hạ tầng cơ bản (Wave 0) và cổng tiếp nhận (Wave 1) để kết nối và nhận dữ liệu, nó được gán cấu hình **Sync Wave: "2"**. Hơn nữa, AI Engine sẽ là nơi ta áp dụng kỹ thuật deploy Canary không gián đoạn bằng **Argo Rollouts**; việc tách riêng file Application giúp ta tách biệt hoàn toàn việc deploy và theo dõi chỉ số Canary (Aborted/Rollback) của AI Engine độc lập với phần còn lại của hệ thống.

---

### 🛠️ Giải thích chi tiết cấu trúc dòng lệnh của `ai-engine.yaml`

#### A. Thuộc tính Sync Wave (Sóng đồng bộ)
```yaml
  annotations:
    argocd.argoproj.io/sync-wave: "2"
```
* **Tại sao cần**: Điều khiển ArgoCD chỉ bắt đầu deploy AI Engine khi các wave `0` và `1` đã hoạt động ổn định và sẵn sàng cung cấp dữ liệu.

#### B. Thư mục mã nguồn overlays (`path`)
```yaml
  source:
    ...
    path: manifests/overlays/sandbox/ai-engine
```
* **Ý nghĩa**: Trỏ đến thư mục overlay của AI Engine. Trong thư mục này, ta sẽ chuyển cấu hình Kubernetes `Deployment` thông thường thành tài nguyên `Rollout` của Argo Rollouts để thực hiện kỹ thuật deploy Canary và Analysis Template tự động rollback.

---
---

## 7. Khởi Tạo Ứng Dụng Con Cho Giám Sát Giám Sát Hệ Thống Observability (`manifests/argocd/apps/observability.yaml`)

### 🔍 Tại sao cần tệp tin này?
Hệ thống giám sát (**Observability**) gồm các thành phần: **Prometheus** (thu thập metrics), **Grafana** (hiển thị dashboard), **Loki** (quản lý logs), và **Alertmanager** (gửi cảnh báo).

Tại sao observability lại được xếp ở **Sync Wave: "4"** (ngoài cùng)?
1. **Tránh nhiễu cảnh báo (Alert Noise)**: Nếu bật monitoring trước khi các service chính chạy, hệ thống giám sát sẽ lập tức bắn hàng loạt cảnh báo "Service down", "Connection Refused" do các pod chính chưa kịp start, gây nhiễu cho SRE.
2. **Không chặn tiến trình chính**: Các công cụ giám sát là cấu phần phụ trợ, không nên chiếm dụng tài nguyên tính toán trước khi các tiến trình ứng dụng cốt lõi của doanh nghiệp được cài đặt xong.

Tách riêng ứng dụng Observability giúp ta dễ dàng cập nhật các rules cảnh báo, cấu hình Grafana Dashboards mà không ảnh hưởng đến luồng hoạt động chính của cụm.

---

### 🛠️ Giải thích chi tiết cấu trúc dòng lệnh của `observability.yaml`

#### A. Thuộc tính Sync Wave (Sóng đồng bộ)
```yaml
  annotations:
    argocd.argoproj.io/sync-wave: "4"
```
* **Tại sao cần**: Đảm bảo toàn bộ hệ thống ứng dụng chính (Wave 0, 1, 2, 3) đã hoàn tất triển khai và ở trạng thái khỏe mạnh thì mới tiến hành khởi tạo hệ thống giám sát.

#### B. Địa chỉ Namespace giám sát (`namespace`)
```yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: tf1-cdo05-sandbox-monitoring
```
* **Ý nghĩa**: Gom toàn bộ tài nguyên giám sát vào namespace `tf1-cdo05-sandbox-monitoring`. Điều này giúp quản lý tập trung và phân bổ quota tài nguyên riêng cho monitoring (tránh việc Prometheus ngốn hết RAM của các pod chạy AI Engine).

---
---

## 8. Cấu Trúc Khai Báo Tài Nguyên Nền Tảng Kustomize (`manifests/base/namespaces-rbac/`)

### 🔍 Tại sao cần Kustomize (Bases & Overlays)?
Khi triển khai ứng dụng lên nhiều môi trường (Sandbox, Staging, Production), cấu hình các file manifest thường giống nhau đến **80%** (cùng tên Service, cùng các port kết nối, cùng cấu hình RBAC). Nếu sao chép thủ công các file YAML này ra 3 thư mục khác nhau, ta sẽ vi phạm nguyên tắc **DRY (Don't Repeat Yourself)**:
* Khi cần đổi tên port hoặc thêm quyền cho nhà phát triển, ta phải sửa thủ công ở cả 3 môi trường. Điều này rất dễ gây ra sai sót, lệch cấu hình và lỗi triển khai.

**Kustomize** giải quyết vấn đề này bằng cách chia làm 2 phần:
1. **Base (Cấu hình gốc)**: Định nghĩa các tài nguyên chuẩn, dùng chung cho tất cả các môi trường (nằm trong `manifests/base/`).
2. **Overlay (Cấu hình ghi đè)**: Định nghĩa các patch, biến đổi nhỏ tùy thuộc vào môi trường (nằm trong `manifests/overlays/{env}/`), ví dụ như thay đổi số lượng bản sao (replicas), giới hạn tài nguyên CPU/RAM, hoặc đính kèm hậu tố môi trường.

---

### 🛠️ Giải thích chi tiết các tệp tin vừa tạo

#### A. Khai báo các không gian tên (`namespaces.yaml`)
Tệp tin định nghĩa 3 Namespace cơ bản của hệ thống:
* `tf1-platform`: Chứa dịch vụ cổng tiếp nhận (Ingest Gateway, Demo App).
* `tf1-ai`: Chứa động cơ phân tích thông minh AI Engine.
* `tf1-monitoring`: Chứa toàn bộ stack giám sát.

#### B. Khai báo phân quyền kiểm soát truy cập (`rbac.yaml`)
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: tf1-developer-readonly
```
* **Ý nghĩa**: Định nghĩa một vai trò trên toàn cụm (`ClusterRole`) có tên `tf1-developer-readonly`.
* **Quyền hạn**: Chỉ cho phép chạy các hành động xem (`get`, `list`, `watch`) trên các tài nguyên cơ bản như `pods`, `logs`, `services`, `deployments`, và cả tài nguyên custom của Argo Rollouts (`rollouts`, `analysisruns`). Điều này giúp ngăn chặn các nhà phát triển vô tình xóa nhầm pod hoặc thay đổi cấu hình deploy trên cụm trực tiếp qua terminal.
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: tf1-dev-readonly-binding
  namespace: tf1-platform
```
* **Ý nghĩa**: Liên kết (`RoleBinding`) vai trò Read-only ở trên cho nhóm người dùng `tf1-developers` (nhóm này được liên kết động từ hệ thống Identity Provider qua OIDC) chỉ bên trong namespace `tf1-platform`.

#### C. Tệp tin chỉ mục Kustomize (`kustomization.yaml` của Base và Overlay)
* **Base `kustomization.yaml`**: Khai báo danh sách các file tài nguyên cần đóng gói gồm `namespaces.yaml` và `rbac.yaml`.
* **Overlay `kustomization.yaml`**: 
  ```yaml
  resources:
    - ../../../base/namespaces-rbac
  ```
  Chỉ đơn giản là kế thừa toàn bộ cấu hình gốc từ Base. Khi chạy lệnh kustomize, hệ thống sẽ tự động tổng hợp đầy đủ cấu hình để ArgoCD áp dụng lên cụm.

---
---

## 9. Khai Báo Tài Nguyên Cổng Tiếp Nhận Platform Service (`manifests/base/platform-service/`)

### 🔍 Tại sao cần các tệp tin này?
**Platform Service** đóng vai trò là cửa ngõ giao tiếp trực tiếp để nhận thông tin sự cố. Khi viết code Docker và deploy Kubernetes, ta cần định cấu hình:
1. **Deployment (`deployment.yaml`)**: Để khởi tạo và duy trì các bản sao (Pods) chạy container code thật.
2. **Service (`service.yaml`)**: Làm trung gian phân phối tải mạng (Internal Load Balancer) cho các Pods.
3. **HPA (`hpa.yaml`)**: Để tự động co giãn số lượng Pods dựa trên độ chịu tải thực tế để tránh sập app hoặc lãng phí tiền.

---

### 🛠️ Giải thích chi tiết các tệp tin vừa tạo

#### A. Cấu hình triển khai Container (`deployment.yaml`)
```yaml
spec:
  replicas: 2
```
* **Ý nghĩa**: Mặc định chạy 2 bản sao (Pods) song song để đảm bảo tính sẵn sàng cao (High Availability). Nếu 1 pod bị lỗi đột ngột, pod còn lại vẫn xử lý traffic bình thường.
```yaml
          resources:
            requests:
              cpu: "100m"
              memory: "128Mi"
            limits:
              cpu: "500m"
              memory: "512Mi"
```
* **Tại sao cần**: Giới hạn tài nguyên để bảo vệ cụm EKS.
  * **`requests`**: Lượng CPU/RAM tối thiểu Kubernetes dành riêng cho container khi khởi chạy.
  * **`limits`**: Giới hạn tối đa container được phép sử dụng. Nếu app bị tràn bộ nhớ (Memory Leak) vượt quá `512Mi`, Kubernetes sẽ tự động kill container đó (OOMKilled) để bảo vệ các app khác cùng chạy trên server.
```yaml
          livenessProbe:
            httpGet:
              path: /healthz
              port: 8080
```
* **Ý nghĩa của Probes (Cơ chế tự kiểm tra sức khỏe)**:
  * **`livenessProbe`**: Liên tục gửi request HTTP `/healthz` cứ sau 20 giây. Nếu container bị đóng băng (Deadlock) và không trả lời, Kubernetes sẽ tự khởi động lại (restart) container đó.
  * **`readinessProbe`**: Kiểm tra xem container đã sẵn sàng nhận traffic thực tế chưa. Khi container mới start, nó cần kết nối database, khởi động môi trường. Bước này đảm bảo chỉ khi app trả về code 200 tại `/healthz` thì Kubernetes mới điều hướng traffic người dùng vào pod.

#### B. Cấu hình mạng dịch vụ (`service.yaml`)
```yaml
spec:
  ports:
    - port: 8080
      targetPort: 8080
  selector:
    app: tf1-platform-service
  type: ClusterIP
```
* **Ý nghĩa**: Tạo địa chỉ IP ảo tĩnh trong cụm EKS. Nó sẽ tự động định tuyến traffic gửi đến cổng `8080` của Service trực tiếp đến cổng `8080` của các Pods có nhãn `app: tf1-platform-service` đang hoạt động khỏe mạnh.

#### C. Tự động co giãn tài nguyên (`hpa.yaml`)
```yaml
  minReplicas: 2
  maxReplicas: 6
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 80
```
* **Ý nghĩa**: Nếu tải CPU trung bình của các pods vượt quá 80% (do lượng alert đổ về tăng đột biến), Kubernetes sẽ tự động nhân bản thêm pods (tối đa là 6). Khi hết giờ cao điểm và tải giảm xuống, nó sẽ tự động thu hồi (scale down) về 2 pods để tiết kiệm chi phí.

#### D. Ghi đè cấu hình môi trường Sandbox (`manifests/overlays/sandbox/platform-service/kustomization.yaml`)
```yaml
replicas:
  - name: tf1-platform-service
    count: 1
```
* **Tại sao cần**: Trong môi trường thử nghiệm (Sandbox), lượng traffic cực kỳ ít và không cần dự phòng cao. Việc ghi đè `replicas: 1` giúp ta tắt bớt pods thừa, tiết kiệm chi phí vận hành máy ảo trên AWS Sandbox mà không cần sửa đổi tệp cấu hình gốc Base.

---
---

## 10. Khai Báo Tài Nguyên Động Cơ AI Engine Với Chiến Lược Canary (`manifests/base/ai-engine/`)

### 🔍 Tại sao cần các tệp tin này?
**AI Engine** là cấu phần phân tích quan trọng bậc nhất. Khi deploy phiên bản AI mới, nếu có lỗi logic, toàn bộ hệ thống gợi ý khắc phục sự cố sẽ bị tê liệt.
Để tránh rủi ro này, chúng ta sử dụng **Argo Rollouts** thay thế cho Deployment mặc định của Kubernetes:
1. **Rollout (`rollout.yaml`)**: Cho phép triển khai kiểu **Canary (Chia nhỏ traffic để thử nghiệm)** thay vì thay thế hàng loạt.
2. **Service (`service.yaml`)**: Định tuyến lưu lượng vào cụm Pods của AI Engine.

---

### 🛠️ Giải thích chi tiết các tệp tin vừa tạo

#### A. Chiến lược phân phối Canary (`rollout.yaml`)
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
```
* **Ý nghĩa**: Sử dụng Custom Resource `Rollout` của Argo Rollouts (thay thế cho `Deployment`). Nó có cấu trúc template pod giống hệt Deployment nhưng bổ sung thêm chiến lược deploy nâng cao.
```yaml
  strategy:
    canary:
      analysis:
        templates:
          - templateName: tf1-ai-engine-success-rate
```
* **Ý nghĩa**: Tích hợp phân tích tự động. Trong lúc deploy Canary, hệ thống sẽ tự động gọi AnalysisTemplate có tên `tf1-ai-engine-success-rate` để đo đạc chất lượng của phiên bản mới.
```yaml
      steps:
        - setWeight: 10
        - pause: {} # Pause indefinitely until manually approved (SRE Promotion Gate)
        - setWeight: 30
        - pause: { duration: 10m }
        - setWeight: 60
        - pause: { duration: 10m }
```
* **Giải thích chi tiết các bước deploy (Canary Steps)**:
  * **Bước 1 (`setWeight: 10`)**: Chỉ điều hướng đúng 10% lượng traffic người dùng thật sang Pods phiên bản mới (vừa build xong), 90% còn lại vẫn dùng phiên bản cũ ổn định.
  * **Bước 2 (`pause: {}`)**: Dừng vô thời hạn. Đây là **SRE Promotion Gate (Cổng phê duyệt thủ công)**. SRE sẽ vào xem log, nếu thấy 10% traffic chạy ổn, SRE bấm nút "Promote" trên giao diện ArgoCD/CLI để tiếp tục.
  * **Bước 3 (`setWeight: 30` & `pause: 10m`)**: Nâng lên 30% traffic và dừng theo dõi tự động trong 10 phút.
  * **Bước 4 (`setWeight: 60` & `pause: 10m`)**: Nâng lên 60% traffic và dừng theo dõi tự động trong 10 phút.
  * **Bước cuối cùng (Tự động nâng lên 100%)**: Hoàn tất cập nhật, toàn bộ cụm chuyển sang phiên bản mới.

#### B. Cấu hình mạng dịch vụ cho AI Engine (`service.yaml`)
* Thiết lập Service loại `ClusterIP` lắng nghe cổng `5000` của AI Engine. Mọi request nội bộ từ CDO Correlator Worker sẽ kết nối thông qua endpoint này để yêu cầu AI phân loại sự cố.

---
---

## 11. Tự Động Hóa Giám Sát Và Rollback Tự Động (`manifests/base/ai-engine/analysis-template.yaml`)

### 🔍 Tại sao cần tệp tin này?
Trong quá trình triển khai Canary, nếu phiên bản AI mới bị lỗi logic (ví dụ: liên tục trả về lỗi HTTP 500 khi nhận alert, khiến hệ thống tê liệt), làm thế nào để phát hiện sớm và thu hồi?
Nếu chờ đợi kỹ sư phát hiện thủ công và chạy lệnh rollback bằng tay, thiệt hại có thể đã xảy ra trên diện rộng và MTTR (Mean Time to Resolution) sẽ tăng cao.

Tệp tin `analysis-template.yaml` định nghĩa **`AnalysisTemplate`** (Mẫu phân tích chỉ số). Argo Rollouts sẽ tự động kết nối với Prometheus để theo dõi trực tiếp sức khỏe của phiên bản Canary. Nếu phát hiện số lượng lỗi vượt ngưỡng, nó tự động kích hoạt **Automated Rollback (Tự động hoàn trả về bản cũ)** trong vòng vài giây mà không cần con người can thiệp.

---

### 🛠️ Giải thích chi tiết cấu trúc dòng lệnh của `analysis-template.yaml`

#### A. Khai báo Tần suất kiểm tra (Interval)
```yaml
    - name: success-rate
      interval: 1m
```
* **Ý nghĩa**: Cứ mỗi 1 phút trong quá trình deploy, Argo Rollouts sẽ tự động gửi truy vấn Prometheus Query để lấy thông số.

#### B. Ngưỡng thành công & Giới hạn lỗi (Success Condition & Failure Limit)
```yaml
      successCondition: result[0] >= 0.99
      failureLimit: 3
```
* **Giải thích cơ chế bảo vệ**:
  * **`successCondition: result[0] >= 0.99`**: Tỷ lệ request thành công (không bị lỗi 5xx) phải đạt từ **99% trở lên** (tức là tỷ lệ lỗi nhỏ hơn 1%).
  * **`failureLimit: 3`**: Cho phép lỗi tối đa 3 lần kiểm tra. Nếu trong 3 phút liên tiếp, tỷ lệ thành công bị sụt giảm xuống dưới 99%, Argo Rollouts sẽ lập tức đánh giá phiên bản mới là **Fail (Thất bại)**. Nó lập tức dừng tiến trình deploy, chuyển 100% traffic trở lại phiên bản cũ và hủy bỏ (terminate) các Pods lỗi.

#### C. Truy vấn Prometheus (Prometheus Query)
```yaml
          address: http://prometheus-k8s.tf1-monitoring.svc.cluster.local:9090
          query: |
            sum(rate(http_requests_total{app="{{args.service-name}}", status!~"5.*"}[2m]))
            /
            sum(rate(http_requests_total{app="{{args.service-name}}"}[2m]))
```
* **Giải thích thuật toán**:
  * `http_requests_total{app="...", status!~"5.*"}`: Lấy tổng số lượng request HTTP không có mã trạng thái dạng 5xx (như 500 Internal Server Error, 502 Bad Gateway, 503 Service Unavailable).
  * Chia cho tổng số request (`http_requests_total{app="..."}`).
  * Hàm `rate(...)[2m]`: Tính toán tốc độ request trung bình trong 2 phút gần nhất để tránh việc số liệu bị đột biến tức thời do một vài gói tin bị lag.
  * Phép chia này cho ra tỷ lệ phần trăm thành công của ứng dụng.

---
---

## 12. Tệp Tin Đóng Gói Chỉ Mục AI Engine Base (`manifests/base/ai-engine/kustomization.yaml`)

### 🔍 Tại sao cần tệp tin này?
Tệp tin `kustomization.yaml` ở tầng Base đóng vai trò liên kết và quản trị tập trung tất cả các file khai báo riêng lẻ liên quan đến AI Engine bao gồm:
* `rollout.yaml` (Quản lý Pods và chiến lược Canary).
* `service.yaml` (Quản lý mạng dịch vụ).
* `analysis-template.yaml` (Quản lý tự động giám sát chất lượng và rollback).

Việc khai báo trong file này giúp Kustomize hiểu rằng đây là một cụm tài nguyên hợp nhất. Khi môi trường Sandbox hay Production gọi tới thư mục Base của AI Engine, Kustomize sẽ tự động load đồng thời cả 3 file này thay vì ta phải chỉ định thủ công từng file một trong các ứng dụng ArgoCD.

---
---

## 13. Tệp Tin Ghi Đè Môi Trường Sandbox AI Engine Overlay (`manifests/overlays/sandbox/ai-engine/kustomization.yaml`)

### 🔍 Tại sao cần tệp tin này?
Tương tự như cổng tiếp nhận Platform Service, trong môi trường thử nghiệm (Sandbox), chúng ta không cần chạy 2 Pods cho AI Engine.
Việc khai báo ghi đè trong `manifests/overlays/sandbox/ai-engine/kustomization.yaml`:
```yaml
replicas:
  - name: tf1-ai-engine
    count: 1
```
Giúp giảm số lượng Pods hoạt động của AI Engine xuống **1 Pod** để tiết kiệm RAM và CPU cho cụm EKS chạy thử nghiệm. Khi cấu hình cho môi trường Production (`overlays/prod`), chúng ta có thể ghi đè số replicas lên 3 hoặc 4 để phục vụ tải cao của khách hàng thật.

---
---

## 14. Khai Báo Tài Nguyên Giám Sát Prometheus Server (`manifests/base/observability/prometheus.yaml`)

### 🔍 Tại sao cần tệp tin này?
Trong quá trình vận hành, hệ thống cần tự động thu thập và lưu trữ các metric (chỉ số đo lường) từ các microservices.
**Prometheus Server** là hạt nhân của hệ thống giám sát:
1. **ConfigMap (`prometheus-config`)**: Lưu trữ cấu hình cách Prometheus tự quét (scrape) các Pods để lấy chỉ số.
2. **Deployment (`prometheus-k8s`)**: Triển khai Prometheus pod chạy image `prom/prometheus`.
3. **Service (`prometheus-k8s`)**: Cung cấp endpoint nội bộ (port `9090`) để các dịch vụ khác (như Argo Rollouts AnalysisTemplate) có thể truy vấn dữ liệu.

---

### 🛠️ Giải thích chi tiết các cấu phần trong `prometheus.yaml`

#### A. Cấu hình tự động quét Pods (Scrape Config)
```yaml
      - job_name: 'kubernetes-pods'
        kubernetes_sd_configs:
          - role: pod
```
* **Ý nghĩa**: Bật tính năng **Service Discovery** (Tự động phát hiện) của Prometheus. Nó sẽ liên tục truy vấn EKS API để lấy danh sách toàn bộ các Pods đang chạy.
```yaml
          - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
            action: keep
            regex: true
```
* **Tại sao cần**: Đây là cơ chế lọc thông minh. Chỉ những Pods nào có gắn nhãn annotation `prometheus.io/scrape: "true"` thì Prometheus mới tiến hành cào (scrape) metrics, tránh việc thu thập dư thừa làm nghẽn hệ thống.

#### B. Khởi tạo Prometheus Deployment
* Sử dụng image chính thức `prom/prometheus:v2.45.0` chạy ổn định (LTS).
* Gắn cấu hình qua Volume Mount từ ConfigMap `prometheus-config` để Prometheus nạp các quy tắc quét.
* Tạo `emptyDir` làm volume lưu trữ dữ liệu tạm thời cho Sandbox. Ở môi trường Production, bộ lưu trữ này sẽ được đổi thành **AWS EBS Persistent Volume** thông qua StorageClass để dữ liệu metrics không bị mất khi Pod restart.

---
---

## 15. Tệp Tin Đóng Gói Chỉ Mục Observability Base (`manifests/base/observability/kustomization.yaml`)

### 🔍 Tại sao cần tệp tin này?
Tương tự như các microservice khác, file `kustomization.yaml` này giúp tập hợp và quản trị tất cả các thành phần giám sát (ở đây là Prometheus Server và các config map đi kèm) thành một nhóm thống nhất để phục vụ cho khâu kế thừa ở overlays.

---
---

## 16. Tệp Tin Ghi Đè Môi Trường Sandbox Observability Overlay (`manifests/overlays/sandbox/observability/kustomization.yaml`)

### 🔍 Tại sao cần tệp tin này?
Tệp tin này kế thừa toàn bộ cấu trúc thu thập logs/metrics của Prometheus Server cơ bản từ Base để áp dụng lên môi trường Sandbox. Do trong sandbox chúng ta chỉ cần chạy 1 instance Prometheus tối giản, ta không ghi đè thêm tham số phức tạp mà chỉ trỏ trực tiếp về Base nhằm duy trì cấu hình tối giản, dễ kiểm soát.

---
---

## 17. Khai Báo OIDC Provider Cho GitHub Actions (`infra/environments/sandbox/github_oidc.tf`)

### 🔍 Tại sao cần tệp tin này?
Như đã phân tích ở phần **OIDC Authentication** trong Job `plan` và `apply`, để GitHub Actions có thể liên lạc một cách bảo mật với AWS mà không cần lưu trữ bất kỳ static credentials (Access Key/Secret Key) nào trên GitHub Secrets, ta cần thiết lập mối quan hệ tin cậy song phương.

Tệp tin `github_oidc.tf` tự động hóa việc cấu hình này:
1. **OIDC Provider (`aws_iam_openid_connect_provider`)**: Khai báo để AWS tin tưởng các token bảo mật do GitHub cấp.
2. **IAM Role (`aws_iam_role`)**: Tạo ra vai trò `tf1-cdo05-github-actions-role` chỉ chấp nhận kết nối từ đúng repository `Hung0codon/Trigger_Hub`.
3. **IAM Policy (`aws_iam_role_policy`)**: Cấp quyền tối thiểu cần thiết để GitHub Actions thay đổi hạ tầng và đẩy Container Image lên ECR.

---

### 🛠️ Giải thích chi tiết các cấu phần trong `github_oidc.tf`

#### A. Khai báo OIDC Provider cho GitHub Actions
```hcl
data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com"
}
```
* **Ý nghĩa**: Lấy dấu vân tay SSL (`thumbprint`) hiện tại của máy chủ GitHub. Dấu vân tay này bắt buộc phải khớp khi AWS thực hiện bắt tay bảo mật HTTPS với GitHub.
```hcl
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]
}
```
* **Ý nghĩa**: Đăng ký dịch vụ OIDC của GitHub làm nhà cung cấp danh tính (Identity Provider) được ủy quyền trên tài khoản AWS của bạn.

#### B. Cấu hình Trust Policy giới hạn Repository
```hcl
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:Hung0codon/Trigger_Hub:*"
          }
        }
```
* **Tại sao cần bảo mật cực kỳ cao ở đây?**: 
  * Trường `aud` (Audience) bắt buộc phải là `sts.amazonaws.com`.
  * Trường `sub` (Subject) cấu hình bắt buộc token phải đến từ repository **`repo:Hung0codon/Trigger_Hub:*`**. 
  * Điều này đảm bảo rằng **chỉ có các pipeline chạy trên repo của chính bạn** mới có quyền assume-role này. Nếu một hacker Fork dự án của bạn sang một tài khoản GitHub khác và chạy pipeline, AWS sẽ từ chối cấp quyền vì tên repo không khớp với Trust Policy.

#### C. Quyền hạn cấp cho GitHub Actions Policy
* Cấp quyền tương tác đầy đủ với các tài nguyên AWS (EKS, ECR, Lambda, SQS, DynamoDB, S3, EC2) để GitHub Actions có thể thay đổi và cập nhật hạ tầng hoàn chỉnh.















