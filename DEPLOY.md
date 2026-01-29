# EC2/ECS デプロイガイド

## IAMロールベースの認証

このアプリケーションは、EC2/ECS環境では**IAMロールから自動的にAWS認証情報を取得**します。
環境変数にアクセスキーを設定する必要はありません。

## 必要なIAM権限

EC2インスタンスまたはECSタスクにアタッチするIAMロールには、以下の権限が必要です：

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "bedrock:InvokeModel"
      ],
      "Resource": [
        "arn:aws:bedrock:*::foundation-model/anthropic.claude-3-sonnet-20240229-v1:0"
      ]
    }
  ]
}
```

## EC2へのデプロイ

### 1. IAMロールの作成と設定

```bash
# IAMロールを作成（AWSコンソールまたはCLI）
aws iam create-role \
  --role-name bedrock-ui-ec2-role \
  --assume-role-policy-document file://trust-policy.json

# ポリシーをアタッチ
aws iam put-role-policy \
  --role-name bedrock-ui-ec2-role \
  --policy-name BedrockInvokeModel \
  --policy-document file://bedrock-policy.json

# インスタンスプロファイルを作成
aws iam create-instance-profile \
  --instance-profile-name bedrock-ui-ec2-profile

# ロールをインスタンスプロファイルに追加
aws iam add-role-to-instance-profile \
  --instance-profile-name bedrock-ui-ec2-profile \
  --role-name bedrock-ui-ec2-role
```

#### trust-policy.json
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

#### bedrock-policy.json
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "bedrock:InvokeModel"
      ],
      "Resource": [
        "arn:aws:bedrock:*::foundation-model/anthropic.claude-3-sonnet-20240229-v1:0"
      ]
    }
  ]
}
```

### 2. EC2インスタンスの起動

```bash
# IAMロールを指定してEC2を起動
aws ec2 run-instances \
  --image-id ami-xxxxxxxxx \
  --instance-type t3.medium \
  --iam-instance-profile Name=bedrock-ui-ec2-profile \
  --security-group-ids sg-xxxxxxxxx \
  --subnet-id subnet-xxxxxxxxx \
  --user-data file://user-data.sh
```

**既存のEC2にIAMロールをアタッチ:**
```bash
aws ec2 associate-iam-instance-profile \
  --instance-id i-xxxxxxxxx \
  --iam-instance-profile Name=bedrock-ui-ec2-profile
```

### 3. EC2インスタンスでのセットアップ

```bash
# SSHでEC2に接続
ssh -i your-key.pem ec2-user@your-ec2-ip

# Docker & Docker Composeをインストール
sudo yum update -y
sudo yum install -y docker
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -a -G docker ec2-user

# Docker Composeをインストール
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# 再ログイン（Dockerグループ反映のため）
exit
ssh -i your-key.pem ec2-user@your-ec2-ip

# リポジトリをクローン
git clone https://github.com/your-repo/bedrock-ui.git
cd bedrock-ui

# 環境変数ファイルを作成（リージョンのみ）
cat > .env << EOF
AWS_REGION=us-east-1
EOF

# 本番環境用設定でアプリケーションを起動
docker-compose -f docker-compose.prod.yml up -d

# ログを確認
docker-compose -f docker-compose.prod.yml logs -f
```

### 4. 動作確認

```bash
# ヘルスチェック
curl http://localhost:8000/health
curl http://localhost:3000/health

# IAMロールの認証情報が取得できているか確認
docker-compose -f docker-compose.prod.yml exec backend env | grep AWS
```

## ECSへのデプロイ

### 1. IAMロールの作成（ECSタスク用）

```bash
# タスク実行ロール（ECS自体が使用）
aws iam create-role \
  --role-name bedrock-ui-ecs-execution-role \
  --assume-role-policy-document file://ecs-trust-policy.json

aws iam attach-role-policy \
  --role-name bedrock-ui-ecs-execution-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy

# タスクロール（アプリケーションが使用）
aws iam create-role \
  --role-name bedrock-ui-ecs-task-role \
  --assume-role-policy-document file://ecs-trust-policy.json

aws iam put-role-policy \
  --role-name bedrock-ui-ecs-task-role \
  --policy-name BedrockInvokeModel \
  --policy-document file://bedrock-policy.json
```

#### ecs-trust-policy.json
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

### 2. ECRへのイメージプッシュ

```bash
# ECRリポジトリを作成
aws ecr create-repository --repository-name bedrock-ui-backend
aws ecr create-repository --repository-name bedrock-ui-frontend

# ECRにログイン
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin YOUR_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com

# イメージをビルド
docker build -t bedrock-ui-backend ./backend
docker build -t bedrock-ui-frontend ./frontend

# イメージにタグ付け
docker tag bedrock-ui-backend:latest YOUR_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/bedrock-ui-backend:latest
docker tag bedrock-ui-frontend:latest YOUR_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/bedrock-ui-frontend:latest

# ECRにプッシュ
docker push YOUR_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/bedrock-ui-backend:latest
docker push YOUR_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/bedrock-ui-frontend:latest
```

### 3. ECSタスク定義の作成

```json
{
  "family": "bedrock-ui",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "512",
  "memory": "1024",
  "executionRoleArn": "arn:aws:iam::YOUR_ACCOUNT_ID:role/bedrock-ui-ecs-execution-role",
  "taskRoleArn": "arn:aws:iam::YOUR_ACCOUNT_ID:role/bedrock-ui-ecs-task-role",
  "containerDefinitions": [
    {
      "name": "backend",
      "image": "YOUR_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/bedrock-ui-backend:latest",
      "portMappings": [
        {
          "containerPort": 8000,
          "protocol": "tcp"
        }
      ],
      "environment": [
        {
          "name": "AWS_REGION",
          "value": "us-east-1"
        }
      ],
      "healthCheck": {
        "command": ["CMD-SHELL", "curl -f http://localhost:8000/health || exit 1"],
        "interval": 30,
        "timeout": 5,
        "retries": 3,
        "startPeriod": 40
      },
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/bedrock-ui",
          "awslogs-region": "us-east-1",
          "awslogs-stream-prefix": "backend"
        }
      }
    },
    {
      "name": "frontend",
      "image": "YOUR_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/bedrock-ui-frontend:latest",
      "portMappings": [
        {
          "containerPort": 3000,
          "protocol": "tcp"
        }
      ],
      "environment": [
        {
          "name": "REACT_APP_API_URL",
          "value": "http://localhost:8000"
        }
      ],
      "healthCheck": {
        "command": ["CMD-SHELL", "curl -f http://localhost:3000/health || exit 1"],
        "interval": 30,
        "timeout": 5,
        "retries": 3,
        "startPeriod": 60
      },
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/bedrock-ui",
          "awslogs-region": "us-east-1",
          "awslogs-stream-prefix": "frontend"
        }
      },
      "dependsOn": [
        {
          "containerName": "backend",
          "condition": "HEALTHY"
        }
      ]
    }
  ]
}
```

### 4. ECSサービスの作成

```bash
# タスク定義を登録
aws ecs register-task-definition --cli-input-json file://task-definition.json

# ECSクラスターを作成
aws ecs create-cluster --cluster-name bedrock-ui-cluster

# ECSサービスを作成
aws ecs create-service \
  --cluster bedrock-ui-cluster \
  --service-name bedrock-ui-service \
  --task-definition bedrock-ui \
  --desired-count 1 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[subnet-xxx],securityGroups=[sg-xxx],assignPublicIp=ENABLED}" \
  --load-balancers targetGroupArn=arn:aws:elasticloadbalancing:...,containerName=frontend,containerPort=3000
```

## ローカル開発環境

ローカル開発では、AWS認証情報を2つの方法で提供できます：

### 方法1: AWS CLI設定を使用（推奨）

```bash
# AWS CLIで認証情報を設定
aws configure

# ~/.aws/credentials が自動的にマウントされる
docker-compose up
```

### 方法2: 環境変数を使用

```bash
# .envファイルを作成
cp .env.example .env

# .envファイルを編集
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=your_access_key_here
AWS_SECRET_ACCESS_KEY=your_secret_key_here

# アプリケーションを起動
docker-compose up
```

## トラブルシューティング

### IAMロールが正しく設定されているか確認

**EC2の場合:**
```bash
# インスタンスメタデータから確認
curl http://169.254.169.254/latest/meta-data/iam/security-credentials/

# コンテナ内で確認
docker-compose exec backend env | grep AWS
```

**ECSの場合:**
```bash
# CloudWatch Logsで確認
aws logs tail /ecs/bedrock-ui --follow

# タスクロールが正しく設定されているか確認
aws ecs describe-tasks --cluster bedrock-ui-cluster --tasks TASK_ID
```

### 認証エラーが発生する場合

1. IAMロールに`bedrock:InvokeModel`権限があるか確認
2. BedrockがリージョンでModelAccessが有効になっているか確認
3. コンテナがIAMロールのメタデータにアクセスできるか確認

```bash
# Bedrockのモデルアクセスを確認
aws bedrock list-foundation-models --region us-east-1
```

## まとめ

| 環境 | 認証方法 | 設定ファイル |
|------|---------|------------|
| **EC2/ECS** | IAMロール（自動） | `docker-compose.prod.yml` |
| **ローカル** | AWS CLI設定 | `docker-compose.yml` |
| **ローカル** | 環境変数 | `docker-compose.yml` + `.env` |
