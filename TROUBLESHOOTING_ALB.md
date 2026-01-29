# ALB環境でのAPI接続トラブルシューティング

## 問題: フロントエンドがバックエンドAPIに接続できない

### エラーメッセージ
```
POST http://backend:8000/api/chat net::ERR_NAME_NOT_RESOLVED
```

## 原因

フロントエンド（React）は**ブラウザ上で実行**されるため、Dockerコンテナ内部のホスト名（`backend`）にはアクセスできません。

```
❌ 間違った構成:
ブラウザ → backend:8000 (到達不可能！)

✅ 正しい構成:
ブラウザ → ALB (example.com) → /api/* → Backend Container (8000)
```

## 解決策

### ステップ1: フロントエンドコードの確認

フロントエンドのAPIリクエストが**相対パス**を使用していることを確認：

```javascript
// ✅ 正しい（相対パス）
const API_URL = '';
axios.post(`${API_URL}/api/chat`, data);
// → リクエスト先: https://your-alb.com/api/chat

// ❌ 間違い（絶対パス）
const API_URL = 'http://backend:8000';
axios.post(`${API_URL}/api/chat`, data);
// → リクエスト先: http://backend:8000/api/chat（到達不可能）
```

**修正済みのコード:**
- `frontend/src/components/Chat.js`
- `frontend/src/components/DiagramGenerator.js`
- `frontend/src/components/MCPConfig.js`

すべて `const API_URL = process.env.REACT_APP_API_URL || '';` に変更済み。

### ステップ2: docker-compose.prod.yml の確認

本番環境用のDocker Compose設定で、環境変数 `REACT_APP_API_URL` を**設定しない**こと：

```yaml
# ✅ 正しい設定（本番環境）
services:
  frontend:
    # environment セクションをコメントアウトまたは削除
    # environment:
    #   - REACT_APP_API_URL=
```

### ステップ3: ALBリスナールールの設定

**重要:** ルールの優先度順位を正しく設定すること。

#### リスナールール設定（HTTPS 443ポート）

**ルール1（優先度: 1）- API リクエスト**
- **IF（条件）**: パスパターン
  - `/api/*`
  - `/health`
  - `/docs`
- **THEN（アクション）**: `bedrock-ui-backend-tg` に転送
- **重要**: このルールの優先度を **1** に設定

**ルール2（優先度: 2）- デフォルト**
- **IF（条件）**: デフォルト（すべてのリクエスト）
- **THEN（アクション）**: `bedrock-ui-frontend-tg` に転送

#### AWS CLIでルールを作成

```bash
# バックエンド用ルール（優先度: 1）
aws elbv2 create-rule \
  --listener-arn arn:aws:elasticloadbalancing:REGION:ACCOUNT:listener/app/ALB-NAME/xxx/xxx \
  --priority 1 \
  --conditions Field=path-pattern,Values='/api/*','/health','/docs' \
  --actions Type=forward,TargetGroupArn=arn:aws:elasticloadbalancing:REGION:ACCOUNT:targetgroup/bedrock-ui-backend-tg/xxx

# デフォルトルールはリスナーに既に存在するため、編集するのみ
aws elbv2 modify-rule \
  --rule-arn arn:aws:elasticloadbalancing:REGION:ACCOUNT:listener-rule/app/ALB-NAME/xxx/xxx \
  --actions Type=forward,TargetGroupArn=arn:aws:elasticloadbalancing:REGION:ACCOUNT:targetgroup/bedrock-ui-frontend-tg/xxx
```

### ステップ4: コンテナの再ビルド

```bash
# イメージを再ビルド
docker-compose -f docker-compose.prod.yml build --no-cache frontend

# コンテナを再起動
docker-compose -f docker-compose.prod.yml up -d
```

## 確認方法

### 1. ブラウザの開発者ツールで確認

1. ブラウザでアプリケーションを開く（例: `https://your-alb.com`）
2. 開発者ツールを開く（F12）
3. **Networkタブ**を選択
4. チャットでメッセージを送信
5. リクエストURLを確認

**✅ 正しい例:**
```
Request URL: https://your-alb.com/api/chat
Status: 200 OK
```

**❌ 間違った例:**
```
Request URL: http://backend:8000/api/chat
Status: (failed) net::ERR_NAME_NOT_RESOLVED
```

### 2. ALBアクセスログで確認

```bash
# ALBアクセスログを有効化（S3バケット必要）
aws elbv2 modify-load-balancer-attributes \
  --load-balancer-arn arn:aws:elasticloadbalancing:... \
  --attributes Key=access_logs.s3.enabled,Value=true \
               Key=access_logs.s3.bucket,Value=my-alb-logs

# ログを確認
aws s3 ls s3://my-alb-logs/AWSLogs/ACCOUNT-ID/elasticloadbalancing/REGION/
```

期待されるログエントリ:
```
https 2024-01-29T12:00:00.000000Z app/my-alb/xxx 1.2.3.4:12345 10.0.1.10:8000 0.001 0.002 0.000 200 200 123 456 "POST https://your-alb.com:443/api/chat HTTP/2.0" ...
```

### 3. curlでテスト

```bash
# ALB経由でバックエンドにアクセス
curl -X POST https://your-alb.com/api/chat \
  -H "Content-Type: application/json" \
  -d '{"message":"test","conversation_history":[]}'

# 期待されるレスポンス:
# {"response":"...","conversation_history":[...]}
```

## よくある間違い

### ❌ 間違い1: 環境変数に内部ホスト名を設定
```yaml
# docker-compose.prod.yml
environment:
  - REACT_APP_API_URL=http://backend:8000  # ❌ ブラウザから到達不可
```

### ❌ 間違い2: ALBルールの優先度が逆
```
優先度 1: デフォルトルール → frontend  # ❌ これが先だと /api/* がフロントエンドに送られる
優先度 2: /api/* → backend
```

### ❌ 間違い3: CORSエラーを無視
フロントエンドとバックエンドが異なるオリジンの場合、CORS設定が必要：

```python
# backend/main.py
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # 本番環境では適切なオリジンを指定
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
```

## デバッグコマンド集

```bash
# 1. コンテナが正常に起動しているか確認
docker-compose -f docker-compose.prod.yml ps

# 2. コンテナログを確認
docker-compose -f docker-compose.prod.yml logs frontend
docker-compose -f docker-compose.prod.yml logs backend

# 3. コンテナ内で環境変数を確認
docker-compose -f docker-compose.prod.yml exec frontend env | grep REACT_APP

# 4. コンテナ内からバックエンドにアクセス可能か確認
docker-compose -f docker-compose.prod.yml exec frontend curl http://backend:8000/health

# 5. ホストからコンテナにアクセス可能か確認
curl http://localhost:3000/health
curl http://localhost:8000/health

# 6. ALBのターゲットグループの状態を確認
aws elbv2 describe-target-health \
  --target-group-arn arn:aws:elasticloadbalancing:...

# 7. ALBのリスナールールを確認
aws elbv2 describe-rules \
  --listener-arn arn:aws:elasticloadbalancing:...
```

## まとめ

### ALB環境でのAPI接続の仕組み

```
┌─────────────┐
│   Browser   │
└──────┬──────┘
       │ https://your-alb.com/api/chat
       ▼
┌─────────────┐
│     ALB     │
└──────┬──────┘
       │ ルーティング判定:
       │ - /api/* → Backend (8000)
       │ - その他 → Frontend (3000)
       │
       ├────────────────┐
       │                │
       ▼                ▼
┌──────────┐    ┌──────────┐
│ Frontend │    │ Backend  │
│  (3000)  │    │  (8000)  │
└──────────┘    └──────────┘
```

### チェックリスト

- [ ] フロントエンドのコードで相対パス（`''`）を使用
- [ ] `docker-compose.prod.yml` で環境変数未設定
- [ ] ALBリスナールールで `/api/*` を優先度1でバックエンドにルーティング
- [ ] セキュリティグループでポート3000と8000を許可
- [ ] ターゲットグループのヘルスチェックが成功
- [ ] ブラウザのネットワークタブで正しいURLにリクエスト送信を確認
