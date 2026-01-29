# ALB環境へのデプロイ手順

## 修正内容の概要

フロントエンドが自動的に環境を検知して、適切なAPI URLを使用するように修正しました：

- **ローカル開発** (`localhost`): `http://localhost:8000` を使用
- **本番環境** (ALB): 相対パス（空文字列）を使用 → ALB経由でバックエンドに接続

## デプロイ手順

### 1. コードの取得

```bash
# 最新のコードを取得
cd /path/to/bedrock-ui
git pull origin main  # または最新のコードを取得
```

### 2. 環境変数の確認

```bash
# .envファイルを確認（存在する場合）
cat .env

# REACT_APP_API_URL が設定されている場合は削除またはコメントアウト
# AWS_REGIONのみ残す
cat > .env << 'EOF'
AWS_REGION=us-east-1
EOF
```

### 3. フロントエンドの再ビルド

```bash
# 古いコンテナとイメージを削除
docker-compose -f docker-compose.prod.yml down
docker rmi bedrock-ui-frontend bedrock-ui-backend 2>/dev/null || true

# キャッシュなしで再ビルド
docker-compose -f docker-compose.prod.yml build --no-cache

# 起動
docker-compose -f docker-compose.prod.yml up -d
```

### 4. 動作確認

#### a. コンテナの状態を確認

```bash
docker-compose -f docker-compose.prod.yml ps

# 期待される出力:
# NAME       STATUS
# backend    Up (healthy)
# frontend   Up (healthy)
```

#### b. ヘルスチェック

```bash
# バックエンド
curl http://localhost:8000/health
# 期待: {"status":"healthy","service":"bedrock-ui-backend"}

# フロントエンド
curl http://localhost:3000/health
# 期待: {"status":"healthy",...}
```

#### c. ログの確認

```bash
# エラーがないか確認
docker-compose -f docker-compose.prod.yml logs frontend | tail -20
docker-compose -f docker-compose.prod.yml logs backend | tail -20
```

### 5. ALBの設定確認

#### リスナールール（HTTPS 443）

AWSコンソール → EC2 → Load Balancers → あなたのALB → Listeners

**ルール1（優先度: 1）**
- IF: パスパターン
  - `/api/*`
  - `/health` （バックエンドのヘルスチェック）
  - `/docs` （API ドキュメント）
- THEN: `bedrock-ui-backend-tg` に転送

**ルール2（優先度: デフォルト）**
- IF: デフォルト
- THEN: `bedrock-ui-frontend-tg` に転送

### 6. ブラウザで動作確認

#### a. フロントエンドにアクセス

```
https://your-alb-domain.com
```

#### b. 開発者ツールで確認

1. ブラウザで **F12** を押して開発者ツールを開く
2. **Network** タブを選択
3. チャットでメッセージを入力して送信
4. リクエストURLを確認

**✅ 正しい例:**
```
Request URL: https://your-alb-domain.com/api/chat
Method: POST
Status: 200 OK
```

**❌ 間違った例:**
```
Request URL: http://localhost:8000/api/chat
Status: (failed) net::ERR_CONNECTION_REFUSED
```

または

```
Request URL: http://backend:8000/api/chat
Status: (failed) net::ERR_NAME_NOT_RESOLVED
```

#### c. コンソールでエラー確認

開発者ツールの **Console** タブでエラーがないことを確認。

### 7. トラブルシューティング

#### 問題: まだ `localhost` に接続しようとする

**原因**: ブラウザのキャッシュ

**解決策**:
```bash
# ブラウザで Ctrl+Shift+R（強制リロード）
# または
# ブラウザのキャッシュをクリア
```

#### 問題: CORS エラー

**エラーメッセージ**:
```
Access to XMLHttpRequest at 'https://your-alb.com/api/chat' from origin 'https://your-alb.com' has been blocked by CORS policy
```

**原因**: バックエンドのCORS設定

**解決策**: backend/main.py を確認
```python
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # 本番環境では適切に設定
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
```

#### 問題: API リクエストが 404 エラー

**原因**: ALBのリスナールールが正しく設定されていない

**解決策**:
1. ALBコンソールでリスナールールを確認
2. `/api/*` ルールの優先度が1であることを確認
3. ルールが `bedrock-ui-backend-tg` に転送していることを確認

#### 問題: ターゲットグループが Unhealthy

**確認コマンド**:
```bash
# ターゲットグループの状態を確認
aws elbv2 describe-target-health \
  --target-group-arn arn:aws:elasticloadbalancing:REGION:ACCOUNT:targetgroup/bedrock-ui-backend-tg/xxx

aws elbv2 describe-target-health \
  --target-group-arn arn:aws:elasticloadbalancing:REGION:ACCOUNT:targetgroup/bedrock-ui-frontend-tg/xxx
```

**解決策**:
1. セキュリティグループでポート8000と3000が開いているか確認
2. ヘルスチェックパスが `/health` であることを確認
3. コンテナが正常に起動しているか確認

## ECSへのデプロイ

ECSにデプロイする場合は、ECRにイメージをプッシュしてください：

```bash
# ECRにログイン
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin \
  YOUR_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com

# イメージをビルド
docker build -t bedrock-ui-frontend ./frontend
docker build -t bedrock-ui-backend ./backend

# タグ付け
docker tag bedrock-ui-frontend:latest \
  YOUR_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/bedrock-ui-frontend:latest

docker tag bedrock-ui-backend:latest \
  YOUR_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/bedrock-ui-backend:latest

# プッシュ
docker push YOUR_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/bedrock-ui-frontend:latest
docker push YOUR_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/bedrock-ui-backend:latest

# ECSサービスを更新
aws ecs update-service \
  --cluster bedrock-ui-cluster \
  --service bedrock-ui-service \
  --force-new-deployment
```

## まとめ

### リクエストの流れ

```
┌──────────────┐
│   Browser    │
│ (JavaScript) │
└──────┬───────┘
       │ https://your-alb.com/api/chat
       ▼
┌──────────────┐
│     ALB      │
└──────┬───────┘
       │ ルーティング:
       │ /api/* → Backend:8000
       │ その他 → Frontend:3000
       │
       ├─────────────────┐
       │                 │
       ▼                 ▼
┌────────────┐    ┌────────────┐
│  Frontend  │    │  Backend   │
│ (React)    │    │ (FastAPI)  │
│   :3000    │    │   :8000    │
└────────────┘    └────────────┘
```

### 重要ポイント

✅ フロントエンドは自動的に環境を検知
✅ 本番環境では相対パス（空文字列）を使用
✅ ALBリスナールールで `/api/*` をバックエンドにルーティング
✅ 環境変数 `REACT_APP_API_URL` は設定しない

これでデプロイ完了です！🎉
