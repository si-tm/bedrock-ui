# ALB (Application Load Balancer) 設定ガイド

## 構成概要

```
Internet → ALB → Target Group (Backend:8000) → ECS/EC2
              → Target Group (Frontend:3000) → ECS/EC2
```

## ターゲットグループの設定

### 1. バックエンド用ターゲットグループ

**基本設定:**
- ターゲットグループ名: `bedrock-ui-backend-tg`
- プロトコル: `HTTP`
- ポート: `8000`
- VPC: 適切なVPCを選択

**ヘルスチェック設定:**
- プロトコル: `HTTP`
- パス: `/health`
- ポート: `traffic port` (8000)
- 正常のしきい値: `2` 連続成功
- 非正常のしきい値: `3` 連続失敗（10は多すぎます）
- タイムアウト: `5` 秒
- 間隔: `30` 秒
- 成功コード: `200`

### 2. フロントエンド用ターゲットグループ

**基本設定:**
- ターゲットグループ名: `bedrock-ui-frontend-tg`
- プロトコル: `HTTP`
- ポート: `3000`
- VPC: 適切なVPCを選択

**ヘルスチェック設定:**
- プロトコル: `HTTP`
- パス: `/health`
- ポート: `traffic port` (3000)
- 正常のしきい値: `2` 連続成功
- 非正常のしきい値: `3` 連続失敗
- タイムアウト: `5` 秒
- 間隔: `30` 秒
- 成功コード: `200`

## ALBリスナールールの設定

### 重要: フロントエンドからバックエンドへの接続

フロントエンドはブラウザで実行されるため、**同じALB経由でバックエンドAPIにアクセス**する必要があります。

このアプリケーションでは、相対パス（`/api/*`）を使用して、フロントエンドと同じオリジンからAPIリクエストを送信します。

```
ブラウザ → ALB (example.com)
         │
         ├─ / → Frontend (3000) - UI表示
         │
         └─ /api/* → Backend (8000) - API呼び出し
```

### HTTPSリスナー (443ポート)

**ルールの優先度順位が重要**です！

**ルール1 (優先度: 1): API リクエスト → バックエンド**
- 条件: パスパターンが `/api/*` または `/health` または `/docs`
- アクション: `bedrock-ui-backend-tg` に転送

**ルール2 (優先度: 2): その他すべて → フロントエンド**
- 条件: デフォルト
- アクション: `bedrock-ui-frontend-tg` に転送

### HTTPリスナー (80ポート)
- アクション: HTTPSへリダイレクト (推奨)

## セキュリティグループ設定

### ALBのセキュリティグループ
**インバウンドルール:**
- ポート 80 (HTTP): 0.0.0.0/0
- ポート 443 (HTTPS): 0.0.0.0/0

**アウトバウンドルール:**
- すべてのトラフィック: 0.0.0.0/0

### ECS/EC2のセキュリティグループ
**インバウンドルール:**
- ポート 8000: ALBのセキュリティグループから
- ポート 3000: ALBのセキュリティグループから

**アウトバウンドルール:**
- すべてのトラフィック: 0.0.0.0/0

## トラブルシューティング

### ヘルスチェックが失敗する場合

#### 1. ヘルスチェックパスを確認
```bash
# EC2/ECSコンテナ内で確認
curl http://localhost:8000/health
curl http://localhost:3000/health
```

期待されるレスポンス:
```json
// バックエンド
{"status":"healthy","service":"bedrock-ui-backend"}

// フロントエンド
{"status":"healthy","service":"bedrock-ui-frontend","timestamp":"2024-01-XX..."}
```

#### 2. セキュリティグループを確認
- ALBからターゲット（EC2/ECS）へのトラフィックが許可されているか
- ポート8000と3000が開いているか

#### 3. ターゲットの登録状態を確認
```bash
# AWS CLIで確認
aws elbv2 describe-target-health \
  --target-group-arn arn:aws:elasticloadbalancing:REGION:ACCOUNT:targetgroup/NAME/ID
```

#### 4. コンテナログを確認
```bash
# ECSの場合
aws logs tail /ecs/bedrock-ui-backend --follow

# EC2の場合
docker logs -f bedrock-ui-backend-1
```

### よくある問題と解決策

**問題1: ヘルスチェックが常に失敗する**
- 原因: セキュリティグループでポートが開いていない
- 解決: ECS/EC2のセキュリティグループに、ALBからのインバウンドルールを追加

**問題2: 一部のターゲットだけ失敗する**
- 原因: コンテナが正常に起動していない
- 解決: コンテナログを確認し、アプリケーションエラーを修正

**問題3: 間欠的に失敗する**
- 原因: タイムアウト設定が短すぎる、またはアプリケーションの応答が遅い
- 解決: タイムアウトを10秒に増やす、またはアプリケーションを最適化

**問題4: 非正常のしきい値が高すぎる (10)**
- 原因: 異常を検知するまでに5分 (30秒 × 10回) かかる
- 解決: 非正常のしきい値を3に変更（推奨）

**問題5: フロントエンドがバックエンドAPIに接続できない (ERR_NAME_NOT_RESOLVED)**
- 原因: フロントエンドがDocker内部のホスト名（`backend:8000`）にアクセスしようとしている
- 解決: ALBリスナールールで `/api/*` をバックエンドにルーティング
- 確認方法:
  ```bash
  # ブラウザのコンソールでネットワークタブを確認
  # APIリクエストが https://your-alb.com/api/chat に送られていることを確認
  ```

## 推奨設定のまとめ

| 項目 | バックエンド | フロントエンド |
|------|-------------|---------------|
| ポート | 8000 | 3000 |
| パス | /health | /health |
| 間隔 | 30秒 | 30秒 |
| タイムアウト | 5秒 | 5秒 |
| 正常しきい値 | 2 | 2 |
| **非正常しきい値** | **3** | **3** |
| 成功コード | 200 | 200 |

## ECS Task Definition例

```json
{
  "family": "bedrock-ui",
  "containerDefinitions": [
    {
      "name": "backend",
      "image": "YOUR_ECR_REPO/bedrock-ui-backend:latest",
      "portMappings": [
        {
          "containerPort": 8000,
          "protocol": "tcp"
        }
      ],
      "healthCheck": {
        "command": ["CMD-SHELL", "curl -f http://localhost:8000/health || exit 1"],
        "interval": 30,
        "timeout": 5,
        "retries": 3,
        "startPeriod": 40
      }
    },
    {
      "name": "frontend",
      "image": "YOUR_ECR_REPO/bedrock-ui-frontend:latest",
      "portMappings": [
        {
          "containerPort": 3000,
          "protocol": "tcp"
        }
      ],
      "healthCheck": {
        "command": ["CMD-SHELL", "curl -f http://localhost:3000/health || exit 1"],
        "interval": 30,
        "timeout": 5,
        "retries": 3,
        "startPeriod": 60
      }
    }
  ]
}
```

## モニタリング

### CloudWatch メトリクス
- `HealthyHostCount`: 正常なターゲット数
- `UnHealthyHostCount`: 異常なターゲット数
- `TargetResponseTime`: ターゲットの応答時間

### CloudWatch アラーム設定例
```bash
# 異常なホストが1つ以上ある場合にアラーム
aws cloudwatch put-metric-alarm \
  --alarm-name bedrock-ui-unhealthy-targets \
  --alarm-description "Alert when targets are unhealthy" \
  --metric-name UnHealthyHostCount \
  --namespace AWS/ApplicationELB \
  --statistic Average \
  --period 60 \
  --evaluation-periods 2 \
  --threshold 1 \
  --comparison-operator GreaterThanOrEqualToThreshold
```
