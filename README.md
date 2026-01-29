# bedrock-ui

AWS Bedrockを使用したチャット・構成図生成・MCP設定管理アプリケーション

## 概要

- **バックエンド**: AWS Bedrock Claude モデルを使用したFastAPI
- **フロントエンド**: React（チャット、構成図生成、MCP設定管理）
- **デプロイ**: Docker Compose（EC2/ECS対応）
- **認証**: IAMロールベース（EC2/ECS）またはAWS CLI設定（ローカル開発）

## 主な機能

### 1. チャット機能
- AWS Bedrock の Claude モデルを使用した対話型チャット
- 会話履歴の保持
- リアルタイム応答

### 2. 構成図生成機能
- 自然言語からAWS構成図を自動生成
- Mermaid 記法による可視化
- 生成されたコードの表示

### 3. MCP設定管理
- MCPサーバーの設定をJSON形式で管理
- 設定の保存・読み込み
- JSONフォーマット機能

## クイックスタート

### ローカル開発環境

```bash
# リポジトリをクローン
git clone https://github.com/your-repo/bedrock-ui.git
cd bedrock-ui

# AWS CLIで認証情報を設定
aws configure

# 環境変数を設定
echo "AWS_REGION=us-east-1" > .env

# アプリケーションを起動
docker-compose up --build
```

アクセス:
- フロントエンド: http://localhost:3000
- バックエンドAPI: http://localhost:8000
- API ドキュメント: http://localhost:8000/docs

### EC2/ECS環境

```bash
# 本番環境用設定でアプリケーションを起動
docker-compose -f docker-compose.prod.yml up -d
```

**重要**: EC2/ECS環境では、IAMロールから自動的にAWS認証情報を取得します。

## 必要なIAM権限

EC2インスタンスまたはECSタスクにアタッチするIAMロールには、以下の権限が必要です：

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["bedrock:InvokeModel"],
      "Resource": [
        "arn:aws:bedrock:*::foundation-model/anthropic.claude-3-sonnet-20240229-v1:0"
      ]
    }
  ]
}
```

## ドキュメント

- **[SETUP.md](SETUP.md)**: 詳細なセットアップガイド
- **[DEPLOY.md](DEPLOY.md)**: EC2/ECSへのデプロイ手順
- **[HEALTHCHECK.md](HEALTHCHECK.md)**: ヘルスチェック設定
- **[ALB_SETUP.md](ALB_SETUP.md)**: ALB設定ガイド

## アーキテクチャ

```
┌─────────────────────────────────────────────┐
│              ALB (Optional)                  │
└─────────────────┬───────────────────────────┘
                  │
        ┌─────────┴──────────┐
        │                    │
        ▼                    ▼
┌──────────────┐    ┌──────────────┐
│  Frontend    │    │  Backend     │
│  (React)     │───▶│  (FastAPI)   │
│  Port: 3000  │    │  Port: 8000  │
└──────────────┘    └──────┬───────┘
                            │
                            ▼
                    ┌──────────────┐
                    │ AWS Bedrock  │
                    │   (Claude)   │
                    └──────────────┘
```

## 技術スタック

### バックエンド
- Python 3.11
- FastAPI
- Boto3 (AWS SDK)
- Uvicorn

### フロントエンド
- React 18
- Axios
- Mermaid (構成図レンダリング)
- React Router

### インフラ
- Docker & Docker Compose
- AWS EC2 / ECS
- AWS ALB
- AWS Bedrock

## 開発

### バックエンドのみ起動

```bash
cd backend
pip install -r requirements.txt
uvicorn main:app --reload
```

### フロントエンドのみ起動

```bash
cd frontend
npm install
npm start
```

## トラブルシューティング

### AWS認証エラー

**ローカル開発:**
```bash
# AWS CLIの設定を確認
aws configure list
aws sts get-caller-identity
```

**EC2/ECS:**
```bash
# IAMロールが正しく設定されているか確認
curl http://169.254.169.254/latest/meta-data/iam/security-credentials/
```

### Bedrock APIエラー

```bash
# Bedrockのモデルアクセスを確認
aws bedrock list-foundation-models --region us-east-1

# Model Accessを有効化
# AWSコンソール → Bedrock → Model access → Enable models
```

## ライセンス

MIT
