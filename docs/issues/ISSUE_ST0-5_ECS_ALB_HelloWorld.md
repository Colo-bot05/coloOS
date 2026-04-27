# [ST0-5] ECS / ALB / ECR モジュール作成・STG適用（Hello World デプロイ）

> 親：マスター設計書 §11 / §13 / STEP 0 詳細設計書 §7 / §17
> リポジトリ：https://github.com/Colo-bot05/coloOS
> ブランチ命名：`infra/ST0-5-ecs-alb-helloworld`
> 想定工数：2日
> 依存：ST0-4（VPC / Subnets / SG）
> 後続をブロック：ST0-9（apps/web デプロイ）、ST0-10（apps/api デプロイ）、ST0-24（CI/CD deploy-stg）、ST0-27（DoD実走）

---

## 背景（なぜやるか）

Phase 1 のすべての成果物（業務AI / Memory / 認証）は最終的に ECS Fargate 上で動作する。ECS / ALB / ECR の最小構成を STG に立てて Hello World が外部から見える状態を作ることが、**STEP 0 の最終 DoD（マスター §17.2 の M0 完了条件）**。

加えて、ALB の path-based routing（`/api/*` → api、`/*` → web）と ACM 証明書を最初から正しく配置することで、後続の認証コールバックや API 呼び出しが詰まらず通る。

## 目的

- ECR リポジトリ（web / api）を構築
- ECS Cluster（Fargate）を構築
- ECS Task Definition / Service を web / api で2つ作成
- Application Load Balancer（HTTPS終端）+ Target Group + Listener Rules
- ACM 証明書（Cognito Hosted UI と同 ROOT ドメイン or 別ドメイン）
- Hello World 用 Docker イメージ（最小）を作成し ECR へ push
- STG にデプロイ完了し、`https://stg.coloos-aiws.example/healthz` が 200 を返す状態
- CloudWatch Logs にコンテナログが出ている

---

## 受け入れ条件（Definition of Done）

### A. ECR モジュール (`infra/terraform/modules/ecr/`)

- [ ] `coloos-web` と `coloos-api` の2リポジトリを作成
- [ ] Image scanning ON（push時にスキャン）
- [ ] Lifecycle Policy：直近 20 タグまで保持、untagged は1日で削除
- [ ] outputs：repository_url（web/api それぞれ）

### B. ECS モジュール (`infra/terraform/modules/ecs/`)

- [ ] ECS Cluster `coloos-${env}` 作成、Container Insights 有効
- [ ] Task Definition（web / api）：CPU=512 / Memory=1024（STG 既定）、Fargate、awsvpc
- [ ] ECS Service（web / api）：desired_count=1、deployment_circuit_breaker、deployment_minimum_healthy_percent=100
- [ ] サービス検出（Cloud Map）はPhase 1 では未使用、後続で検討
- [ ] IAM Task Role（最小権限）：Secrets Manager 読み取り、SSM、Bedrock、Cognito（apiのみ）
- [ ] IAM Task Execution Role：ECR pull、CloudWatch Logs put
- [ ] CloudWatch Log Group（`/ecs/coloos-${env}/web`、`.../api`）保持30日
- [ ] outputs：cluster_name、service_names、task_definition_arns

### C. ALB モジュール (`infra/terraform/modules/alb/`)

- [ ] Application Load Balancer（internet-facing、HTTPS:443）
- [ ] HTTP:80 → HTTPS:443 redirect
- [ ] Target Group（web）：path `/`（default）、HTTP:3000、health check `/healthz`
- [ ] Target Group（api）：path `/api/*`、HTTP:8000、health check `/api/healthz`
- [ ] Listener Rule：path `/api/*` → api TG、それ以外 → web TG
- [ ] WAFv2 Web ACL（基本ルール：AWS Managed Rules - Core / Known Bad Inputs）を ALB にアタッチ
- [ ] outputs：alb_dns、alb_arn、target_group_arns

### D. ACM 証明書

- [ ] ACM 証明書（DNS 検証）`*.coloos-aiws.example`（仮ドメイン、実ドメインは宮本さんと確認後決定）
- [ ] Route 53 ホストゾーンが既存ならそこに DNS 検証レコードを自動作成
- [ ] ACM 証明書 ARN を ALB Listener に設定

### E. Hello World イメージ

- [ ] `infra/docker/web.Dockerfile` を Next.js Hello World で作成（`/healthz` を返すだけの最小）
- [ ] `infra/docker/api.Dockerfile` を FastAPI Hello World で作成（`/api/healthz` を返すだけの最小）
- [ ] `scripts/build-and-push.sh`（or GitHub Actions workflow）で ECR へ build/push
- [ ] STG の ECS Service が新イメージで安定動作

### F. envs/stg への組み込み

- [ ] `envs/stg/main.tf` から `module "ecr"` / `module "ecs"` / `module "alb"` を呼び出し
- [ ] Route 53 レコード `stg.coloos-aiws.example` → ALB を作成
- [ ] `terraform apply` 完了
- [ ] ブラウザから `https://stg.coloos-aiws.example/healthz` が 200 を返す
- [ ] `https://stg.coloos-aiws.example/api/healthz` が 200 を返す

### G. ドキュメント

- [ ] `docs/runbook/ecs-deploy.md` を新規作成
  - Hello World ビルド手順
  - ECR への push 手順
  - ECS デプロイの流れ（タスク定義更新 → サービス更新）
  - スケールアップ・ダウン手順
  - ロールバック手順（前タスク定義への戻し方、マスター §22.1）
  - ログの見方（CloudWatch Logs）
  - WAF ログ確認

### H. PR / 運用

- [ ] CLAUDE.md / AGENTS.md セルフチェック
- [ ] AIレビュー（GPT or Gemini）通過
- [ ] STG での `https://stg.coloos-aiws.example/healthz` ブラウザスクショを PR に貼る
- [ ] **マージ後ブランチを削除しない**

---

## 想定実装内容（概要レベル）

### A. ECR モジュール（抜粋）

```hcl
locals {
  repos = ["web", "api"]
}

resource "aws_ecr_repository" "this" {
  for_each             = toset(local.repos)
  name                 = "coloos-${each.value}"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "this" {
  for_each   = aws_ecr_repository.this
  repository = each.value.name
  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 20 tagged"
        selection = {
          tagStatus     = "tagged"
          tagPatternList = ["*"]
          countType     = "imageCountMoreThan"
          countNumber   = 20
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Expire untagged after 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      }
    ]
  })
}
```

### B. ECS Cluster + Task Definition + Service（web 例）

```hcl
resource "aws_ecs_cluster" "main" {
  name = "coloos-${var.env}"
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_cloudwatch_log_group" "web" {
  name              = "/ecs/coloos-${var.env}/web"
  retention_in_days = 30
}

resource "aws_ecs_task_definition" "web" {
  family                   = "coloos-${var.env}-web"
  cpu                      = "512"
  memory                   = "1024"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.web_task.arn

  container_definitions = jsonencode([
    {
      name      = "web"
      image     = "${var.ecr_web_url}:hello"
      essential = true
      portMappings = [{ containerPort = 3000, protocol = "tcp" }]
      environment = [
        { name = "NEXT_PUBLIC_API_BASE", value = "https://stg.coloos-aiws.example/api" }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.web.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "web" {
  name            = "coloos-${var.env}-web"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.web.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.ecs_sg_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.web_target_group_arn
    container_name   = "web"
    container_port   = 3000
  }

  depends_on = [aws_iam_role_policy_attachment.task_execution_pull]
}

# api も同様（containerPort=8000、image=${var.ecr_api_url}:hello）
```

### C. ALB モジュール（抜粋）

```hcl
resource "aws_lb" "main" {
  name               = "coloos-${var.env}-alb"
  internal           = false
  load_balancer_type = "application"
  subnets            = var.public_subnet_ids
  security_groups    = [var.alb_sg_id]
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

resource "aws_lb_listener_rule" "api" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }

  condition {
    path_pattern {
      values = ["/api/*"]
    }
  }
}

resource "aws_lb_target_group" "web" {
  name        = "coloos-${var.env}-web"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"
  health_check {
    path                = "/healthz"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_target_group" "api" {
  name        = "coloos-${var.env}-api"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"
  health_check {
    path                = "/api/healthz"
    matcher             = "200"
  }
}

# HTTP:80 → HTTPS:443 redirect listener も追加（省略）
# WAFv2 Web ACL（managed rules）も追加
```

### D. Hello World Docker 例

**`infra/docker/web.Dockerfile`**

```dockerfile
FROM node:22-alpine AS deps
WORKDIR /app
RUN echo '{"name":"hello","scripts":{"start":"node server.js"}}' > package.json && \
    cat > server.js <<'EOF'
const http = require('http');
const PORT = 3000;
http.createServer((req, res) => {
  if (req.url === '/healthz') { res.writeHead(200); res.end('ok'); return; }
  res.writeHead(200, {'Content-Type':'text/html'});
  res.end('<h1>Colobiz AI Workspace</h1><p>Hello from web</p>');
}).listen(PORT, () => console.log(`web on ${PORT}`));
EOF
EXPOSE 3000
CMD ["node","server.js"]
```

**`infra/docker/api.Dockerfile`**

```dockerfile
FROM python:3.12-slim
WORKDIR /app
RUN pip install --no-cache-dir fastapi uvicorn
RUN cat > main.py <<'EOF'
from fastapi import FastAPI
app = FastAPI()

@app.get("/api/healthz")
def healthz():
    return {"status":"ok","app":"api"}

@app.get("/api")
def root():
    return {"hello":"colobiz-ai-workspace"}
EOF
EXPOSE 8000
CMD ["uvicorn","main:app","--host","0.0.0.0","--port","8000"]
```

> 本 Issue では Hello World で十分。実際のapp実装は ST0-9 / ST0-10 で差し替え。

### E. build & push スクリプト

```bash
#!/usr/bin/env bash
# scripts/build-and-push.sh
set -euo pipefail
ENV=${1:-stg}
REGION=ap-northeast-1
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)

aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ACCOUNT.dkr.ecr.$REGION.amazonaws.com

for SVC in web api; do
  IMG="$ACCOUNT.dkr.ecr.$REGION.amazonaws.com/coloos-$SVC:hello"
  docker build -f infra/docker/$SVC.Dockerfile -t $IMG .
  docker push $IMG
done

# ECS service を強制更新（新タスクを起動させる）
aws ecs update-service --cluster coloos-$ENV --service coloos-$ENV-web --force-new-deployment
aws ecs update-service --cluster coloos-$ENV --service coloos-$ENV-api --force-new-deployment
```

### F. envs/stg/main.tf 組み込み

```hcl
module "ecr" {
  source = "../../modules/ecr"
  env    = var.env
}

module "alb" {
  source              = "../../modules/alb"
  env                 = var.env
  vpc_id              = module.vpc.vpc_id
  public_subnet_ids   = module.vpc.public_subnet_ids
  alb_sg_id           = module.vpc.alb_sg_id
  acm_certificate_arn = module.dns_acm.certificate_arn
}

module "ecs" {
  source                  = "../../modules/ecs"
  env                     = var.env
  region                  = var.region
  ecr_web_url             = module.ecr.repository_urls["web"]
  ecr_api_url             = module.ecr.repository_urls["api"]
  private_subnet_ids      = module.vpc.private_subnet_ids
  ecs_sg_id               = module.vpc.ecs_sg_id
  web_target_group_arn    = module.alb.target_group_arns["web"]
  api_target_group_arn    = module.alb.target_group_arns["api"]
}
```

---

## 想定テスト

| No | 観点 | 操作 | 期待結果 |
|---|---|---|---|
| 1 | terraform plan | `terraform plan` (stg) | エラーなし、リソースが計画通り |
| 2 | terraform apply | apply | ECR / ECS / ALB / ACM / Route53 が作成 |
| 3 | ECR push | `bash scripts/build-and-push.sh stg` | 2 イメージが push 成功 |
| 4 | ECS タスク起動 | `aws ecs list-tasks --cluster coloos-stg` | web / api 各1タスクが RUNNING |
| 5 | TG ヘルス | ALB の Target Group | targets が healthy |
| 6 | web /healthz | `curl https://stg.coloos-aiws.example/healthz` | 200 / "ok" |
| 7 | api /healthz | `curl https://stg.coloos-aiws.example/api/healthz` | 200 / `{"status":"ok"}` |
| 8 | path routing | `/api` → api、`/` → web | 正しく振り分け |
| 9 | HTTP→HTTPS | `curl http://stg...` | 301 で https にリダイレクト |
| 10 | TLS | `openssl s_client -connect stg.coloos-aiws.example:443` | TLS 1.3、ACM 証明書有効 |
| 11 | WAF | OWASP テストパターン | ブロックされる |
| 12 | CloudWatch Logs | `/ecs/coloos-stg/{web,api}` | コンテナログが届く |
| 13 | Container Insights | ECS Cluster → Container Insights | メトリクスが見える |
| 14 | rolling deploy | image を変更して push → service update | ダウンタイム0で切替 |
| 15 | rollback | 前タスク定義に戻す | 動作復旧（マスター §22.1） |

---

## 関連リンク

- マスター設計書 §11 AWS構成 / §13 デプロイブランチ運用 / §22 ロールバック
- STEP 0 詳細設計書 §7 / §13 / §17 Issue一覧（ST0-5）
- ST0-3：Terraform スケルトン
- ST0-4：VPC / RDS（依存）
- ST0-9：apps/web 実装、ST0-10：apps/api 実装、ST0-24：CI/CD deploy-stg（後続）
- CLAUDE.md §6 ブランチ運用とデプロイフロー / §13 CI/CD

---

## 優先度・期限

- 優先度：**最高**
- 期限：ST0-4 完了から3営業日以内

---

## 役割分担

| 担当 | タスク |
|---|---|
| **Claude Code** | ECR / ECS / ALB モジュール HCL、Hello World Dockerfile（web/api）、build-and-push.sh、`docs/runbook/ecs-deploy.md` |
| **AIレビュー** | IAM ロールの最小権限、ALB SSL Policy、TG ヘルスチェック、WAF ルール、CloudWatch ログ |
| **人間（宮本）** | ドメイン決定（仮：`coloos-aiws.example` か実ドメイン）、Route 53 ホストゾーン作成、ACM 証明書の DNS 検証承認、STG での実 apply、ブラウザ動作確認、PR 最終承認 |

---

## リスクと対応

| リスク | 影響 | 対応 |
|---|---|---|
| ACM 証明書発行に時間がかかる | 中 | DNS 検証レコードを Terraform で自動作成、Route 53 ホストゾーンを事前準備 |
| ECS Task が ECR pull で失敗 | 中 | Task Execution Role に `AmazonECSTaskExecutionRolePolicy` をアタッチ確認 |
| Health check 失敗で永続デプロイ失敗 | 高 | deployment_circuit_breaker.rollback=true で自動巻き戻し、health check path を Hello World 側で実装 |
| WAF 過検知で正常リクエストが落ちる | 中 | Phase 1 は Count モードで開始も検討、本番化時に Block へ切替 |
| Cognito Hosted UI と ALB の証明書ドメイン不整合 | 中 | 同 ROOT ドメインに揃える（例：`auth.coloos-aiws.example` / `stg.coloos-aiws.example`） |
| ECR Lifecycle で必要なイメージが消える | 中 | 「直近20」を Phase 1 で十分、必要に応じて増やす |
| 公開エンドポイントが想定外に晒される | 中 | WAFアタッチ＋IP制限を Phase 2 で検討、現状は社内 ACL or VPN |

---

## 補足・注意事項

- **ドメイン名は仮置き**。実際のドメイン（colobiz.co.jp サブ or 別ドメイン）が決まり次第、変数で差し替え
- ECS Service の desired_count は STG=1 で開始。本番は最低2 + Auto Scaling（別 Issue）
- 本 Issue 完了で **STEP 0 の M0：土台完了の最終ピース**。STG に Hello World が見える状態 = STEP 0 の M0 達成
- WAF Web ACL の有効化は STG で一度モニタリング（Count モード）してから Block へ切替が安全
- Cognito Hosted UI ドメイン（ST0-6）と本 Issue の ALB ドメインは **同 Route 53 ホストゾーン**で管理することを推奨

---

**Cowork から Claude Code への申し送り**

ECS / ALB は **設定の組み合わせが多くハマりやすい**領域です。特に health check の path ミス、TG の port ずれ、ALB SG と ECS SG の関係、IAM ロールの権限不足は典型ミス。GPT / Gemini 両方のレビューを通してください（CLAUDE.md §9.4・AGENTS.md §3.4）。

Hello World Dockerfile はインライン記法（heredoc）で簡潔に書いていますが、apps/web / apps/api 実装（ST0-9 / ST0-10）でちゃんとしたマルチステージビルドに差し替える前提です。**本 Issue では「最小で動く」ことが価値**なので、複雑な最適化はしないでください。

ロールバック手順（マスター §22.1）の動作確認まで本 Issue で実走してください。STEP 0 完了後は、これが本番リリース時の最後の砦になります。
