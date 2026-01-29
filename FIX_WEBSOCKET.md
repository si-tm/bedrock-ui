# WebSocketエラーの修正ガイド

## エラー内容

```
WebSocket connection to 'ws://alb-hyakuzuka-891406204.ap-northeast-1.elb.amazonaws.com:3000/ws' failed
```

## 原因

現在のフロントエンドは**開発モード（`npm start`）**で起動しているため、React Hot Module Replacement（HMR）がWebSocketを使用しようとしています。

```
開発モード（npm start）
  ↓
WebSocket使用（HMR）
  ↓
ALB経由でWebSocket接続
  ↓
失敗（ALBがWebSocketをサポートしていない）
```

## 解決策：本番ビルドを使用

本番環境では、静的ファイルとして配信し、WebSocketを使用しません。

### ステップ1: 本番用Dockerfileを使用

```bash
cd /Users/hyakuzukamaya/Desktop/bedrock-ui

# 本番用設定で再ビルド
docker-compose -f docker-compose.prod.yml build --no-cache frontend

# 起動
docker-compose -f docker-compose.prod.yml up -d

# ログを確認
docker-compose -f docker-compose.prod.yml logs -f frontend
```

### ステップ2: 動作確認

```bash
# ヘルスチェック
curl http://localhost:3000/health

# フロントエンドにアクセス
curl http://localhost:3000
```

### ステップ3: ALB経由で確認

ブラウザで以下にアクセス：
```
http://alb-hyakuzuka-891406204.ap-northeast-1.elb.amazonaws.com
```

**WebSocketエラーが出なくなります！**

## 変更内容

### 1. Dockerfile.prod（本番用）

**変更前（開発モード）:**
```dockerfile
CMD ["npm", "start"]  # ← WebSocket使用
```

**変更後（本番モード）:**
```dockerfile
# ビルド
RUN npm run build

# Nginxで静的ファイル配信
FROM nginx:alpine
COPY --from=build /app/build /usr/share/nginx/html
CMD ["nginx", "-g", "daemon off;"]  # ← WebSocket不要
```

### 2. nginx.conf

Nginxで静的ファイルを配信し、ヘルスチェックをサポート：

```nginx
server {
    listen 3000;
    
    # ヘルスチェック
    location /health {
        return 200 '{"status":"healthy"}';
    }
    
    # React Router対応
    location / {
        try_files $uri /index.html;
    }
}
```

### 3. docker-compose.prod.yml

本番用のDocker Compose設定：

```yaml
frontend:
  build:
    context: ./frontend
    dockerfile: Dockerfile.prod  # ← 本番用
```

## 開発環境 vs 本番環境

| 項目 | 開発環境 | 本番環境 |
|------|---------|---------|
| Dockerfile | `Dockerfile` | `Dockerfile.prod` |
| 起動方法 | `npm start` | `nginx` |
| WebSocket | ✅ 使用（HMR） | ❌ 不使用 |
| ホットリロード | ✅ あり | ❌ なし |
| ファイルサイズ | 大きい | 小さい（最適化済み） |
| パフォーマンス | 遅い | 速い |

## トラブルシューティング

### エラー: "npm run build" fails

```bash
# package.jsonにbuildスクリプトがあるか確認
cat /Users/hyakuzukamaya/Desktop/bedrock-ui/frontend/package.json | grep build

# なければ追加
cd /Users/hyakuzukamaya/Desktop/bedrock-ui/frontend
npm install --save-dev react-scripts
```

### エラー: nginx.confが見つからない

```bash
# nginx.confが存在するか確認
ls -la /Users/hyakuzukamaya/Desktop/bedrock-ui/frontend/nginx.conf

# なければ作成（すでに作成済み）
```

### ビルドが遅い

```bash
# node_modulesをキャッシュから除外
echo "node_modules/" >> /Users/hyakuzukamaya/Desktop/bedrock-ui/frontend/.dockerignore
```

## ECS/EC2へのデプロイ

### ECRにプッシュ

```bash
cd /Users/hyakuzukamaya/Desktop/bedrock-ui

# イメージをビルド
docker-compose -f docker-compose.prod.yml build

# ECRにタグ付け
docker tag bedrock-ui-frontend:latest ACCOUNT.dkr.ecr.REGION.amazonaws.com/bedrock-ui-frontend:latest

# プッシュ
docker push ACCOUNT.dkr.ecr.REGION.amazonaws.com/bedrock-ui-frontend:latest
```

### ECSタスク定義

```json
{
  "name": "frontend",
  "image": "ACCOUNT.dkr.ecr.REGION.amazonaws.com/bedrock-ui-frontend:latest",
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
    "startPeriod": 30
  }
}
```

## まとめ

### WebSocketエラーを修正する手順

1. ✅ `docker-compose.prod.yml` を使用
2. ✅ `Dockerfile.prod` で本番ビルド
3. ✅ Nginxで静的ファイル配信
4. ✅ WebSocket不要

### コマンド

```bash
# 開発環境（WebSocketあり）
docker-compose up

# 本番環境（WebSocketなし）
docker-compose -f docker-compose.prod.yml up
```

これでWebSocketエラーが解決します！🎉
