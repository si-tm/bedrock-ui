# ヘルスチェック設定

## 概要

バックエンドとフロントエンドの両方にヘルスチェック機能を実装しました。

## ヘルスチェックエンドポイント

### バックエンド
- URL: `http://localhost:8000/health`
- レスポンス:
```json
{
  "status": "healthy",
  "service": "bedrock-ui-backend"
}
```

### フロントエンド
- URL: `http://localhost:3000/health`
- レスポンス:
```json
{
  "status": "healthy",
  "service": "bedrock-ui-frontend",
  "timestamp": "2024-01-XX..."
}
```

注: `/health.html` も利用可能ですが、ALBとの互換性のため `/health` を推奨します。

## Docker Composeヘルスチェック設定

### バックエンド
- **チェック間隔**: 30秒
- **タイムアウト**: 10秒
- **リトライ回数**: 3回
- **開始待機時間**: 40秒

### フロントエンド
- **チェック間隔**: 30秒
- **タイムアウト**: 10秒
- **リトライ回数**: 3回
- **開始待機時間**: 60秒
- **依存関係**: バックエンドが健全な状態になってから起動

## 確認方法

### コンテナの状態確認
```bash
docker-compose ps
```

ヘルスチェックが成功すると、STATUSに`(healthy)`と表示されます：
```
NAME                STATUS
backend             Up (healthy)
frontend            Up (healthy)
```

### 手動でヘルスチェック実行
```bash
# バックエンド
curl http://localhost:8000/health

# フロントエンド
curl http://localhost:3000/health
# または
curl http://localhost:3000/health.html
```

## AWS環境での利用

### ALB (Application Load Balancer)
ALBのターゲットグループでヘルスチェックを設定：
- **パス（バックエンド）**: `/health`
- **パス（フロントエンド）**: `/health`
- **間隔**: 30秒
- **タイムアウト**: 5秒
- **正常しきい値**: 2
- **異常しきい値**: 3 (推奨、10は多すぎます)

詳細は `ALB_SETUP.md` を参照してください。

### ECS
タスク定義でヘルスチェックコマンドを設定：
```json
{
  "healthCheck": {
    "command": ["CMD-SHELL", "curl -f http://localhost:8000/health || exit 1"],
    "interval": 30,
    "timeout": 10,
    "retries": 3,
    "startPeriod": 40
  }
}
```

## トラブルシューティング

### ヘルスチェックが失敗する場合
1. コンテナのログを確認
```bash
docker-compose logs backend
docker-compose logs frontend
```

2. コンテナ内でcurlが実行できるか確認
```bash
docker-compose exec backend curl http://localhost:8000/health
docker-compose exec frontend curl http://localhost:3000/health.html
```

3. アプリケーションが正常に起動しているか確認
```bash
docker-compose exec backend ps aux
docker-compose exec frontend ps aux
```
