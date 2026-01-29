# Bedrock UI - セットアップガイド

AWS Bedrockを使用したチャット・構成図生成・MCP設定管理アプリケーション

## 前提条件

- Docker & Docker Compose
- AWS アカウント（Bedrock へのアクセス権限）
- **EC2/ECS環境**: IAMロール（bedrock:InvokeModel 権限）
- **ローカル開発**: AWS CLI設定またはAWSアクセスキー

## セットアップ手順

### 1. 環境変数の設定

#### ローカル開発環境

**方法1: AWS CLI設定を使用（推奨）**

```bash
# AWS CLIで認証情報を設定
aws configure

# .envファイルにリージョンのみ設定
cat > .env << EOF
AWS_REGION=us-east-1
EOF
```

**方法2: 環境変数を使用**

```bash
# .env.exampleをコピー
cp .env.example .env

# .envファイルを編集して、AWS認証情報を設定：
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=your_access_key_here
AWS_SECRET_ACCESS_KEY=your_secret_key_here
REACT_APP_API_URL=http://localhost:8000
```

#### EC2/ECS環境

IAMロールから自動的に認証情報を取得します。
詳細は `DEPLOY.md` を参照してください。

### 2. Docker Compose でアプリケーションを起動

```bash
docker-compose up --build
```

### 3. アプリケーションへのアクセス

- フロントエンド: http://localhost:3000
- バックエンドAPI: http://localhost:8000
- API ドキュメント: http://localhost:8000/docs

### 4. ヘルスチェック

各サービスのヘルスチェックエンドポイント：

- バックエンド: http://localhost:8000/health
- フロントエンド: http://localhost:3000/health

Docker Composeは自動的にヘルスチェックを実行します：

```bash
# コンテナの状態を確認
docker-compose ps
```

ヘルスチェックの設定：
- バックエンド: 30秒間隔、10秒タイムアウト、3回リトライ、起動40秒後から開始
- フロントエンド: 30秒間隔、10秒タイムアウト、3回リトライ、起動60秒後から開始
- フロントエンドはバックエンドが健全な状態になってから起動

詳細は `HEALTHCHECK.md` を参照してください。

## 機能

### 1. チャット機能
- AWS Bedrock の Claude モデルを使用したチャット
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

## AWS EC2/ECS へのデプロイ

**重要**: EC2/ECSでは、IAMロールから自動的にAWS認証情報を取得します。
環境変数にアクセスキーを設定する必要はありません。

詳細な手順は `DEPLOY.md` を参照してください。

### EC2 へのデプロイ

1. EC2インスタンスにIAMロールをアタッチ（bedrock:InvokeModel 権限）
2. Docker & Docker Composeをインストール
3. リポジトリをクローン
4. 本番環境用設定で起動: `docker-compose -f docker-compose.prod.yml up -d`

### ECS へのデプロイ

1. ECRにイメージをプッシュ
2. ECSタスク定義を作成（タスクロールにbedrock:InvokeModel権限を付与）
3. ECSサービスを作成
4. ALBでルーティングを設定

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

### Bedrock APIエラー
- AWS認証情報が正しく設定されているか確認
- IAMユーザー/ロールに bedrock:InvokeModel 権限があるか確認
- 使用しているリージョンでBedrockが利用可能か確認

### Docker接続エラー
- Dockerデーモンが起動しているか確認
- ポート3000, 8000が使用されていないか確認

## ライセンス

MIT
