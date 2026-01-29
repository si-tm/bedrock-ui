# MCP Server 統合ガイド

## 概要

MCPサーバーをbedrock-uiに統合し、システム情報とAWS情報をモニタリングできるようにします。

## MCPサーバーの機能

### システム情報
- CPU使用率
- メモリ使用率
- ディスク使用率

### AWS情報
- EC2インスタンス一覧
- S3バケット一覧
- RDSインスタンス一覧

## セットアップ

### 前提条件

mcp-serverフォルダがbedrock-uiと同じ階層にあること：

```
Desktop/
├── bedrock-ui/
└── mcp-server/
```

### 1. MCPサーバーを起動

```bash
cd /Users/hyakuzukamaya/Desktop/bedrock-ui

# Docker Composeで全てのサービスを起動
docker-compose up -d

# ログを確認
docker-compose logs mcp-server
```

### 2. 動作確認

```bash
# ヘルスチェック
curl http://localhost:9000/health

# CPU使用率を取得
curl http://localhost:9000/cpu

# ツール一覧を取得
curl http://localhost:9000/tools
```

## APIエンドポイント

### ポート: 9000

#### 基本情報
```bash
# サーバー情報
GET http://localhost:9000/

# ヘルスチェック
GET http://localhost:9000/health

# 利用可能なツール一覧
GET http://localhost:9000/tools
```

#### システム情報
```bash
# CPU使用率
GET http://localhost:9000/cpu

# メモリ使用率
GET http://localhost:9000/memory

# ディスク使用率
GET http://localhost:9000/disk
```

#### AWS情報
```bash
# EC2インスタンス一覧
GET http://localhost:9000/aws/ec2

# S3バケット一覧
GET http://localhost:9000/aws/s3

# RDSインスタンス一覧
GET http://localhost:9000/aws/rds
```

#### 汎用ツール実行
```bash
POST http://localhost:9000/execute
Content-Type: application/json

{
  "tool_name": "get_cpu_usage",
  "arguments": {}
}
```

## フロントエンドからの利用

### 環境変数

`.env` ファイルに追加：

```bash
# MCP Server URL（ローカル開発）
REACT_APP_MCP_URL=http://localhost:9000
```

### React コンポーネント例

```jsx
import React, { useState, useEffect } from 'react';
import axios from 'axios';

const MCP_URL = process.env.REACT_APP_MCP_URL || 'http://localhost:9000';

function SystemMonitor() {
  const [cpuUsage, setCpuUsage] = useState(null);
  const [memoryUsage, setMemoryUsage] = useState(null);
  const [ec2Instances, setEc2Instances] = useState([]);

  useEffect(() => {
    // CPU使用率を取得
    const fetchCpuUsage = async () => {
      try {
        const response = await axios.get(`${MCP_URL}/cpu`);
        if (response.data.success) {
          setCpuUsage(response.data.data);
        }
      } catch (error) {
        console.error('Error fetching CPU usage:', error);
      }
    };

    // メモリ使用率を取得
    const fetchMemoryUsage = async () => {
      try {
        const response = await axios.get(`${MCP_URL}/memory`);
        if (response.data.success) {
          setMemoryUsage(response.data.data);
        }
      } catch (error) {
        console.error('Error fetching memory usage:', error);
      }
    };

    // EC2インスタンス一覧を取得
    const fetchEc2Instances = async () => {
      try {
        const response = await axios.get(`${MCP_URL}/aws/ec2`);
        if (response.data.success) {
          setEc2Instances(response.data.data.instances);
        }
      } catch (error) {
        console.error('Error fetching EC2 instances:', error);
      }
    };

    fetchCpuUsage();
    fetchMemoryUsage();
    fetchEc2Instances();

    // 30秒ごとに更新
    const interval = setInterval(() => {
      fetchCpuUsage();
      fetchMemoryUsage();
      fetchEc2Instances();
    }, 30000);

    return () => clearInterval(interval);
  }, []);

  return (
    <div className="system-monitor">
      <h2>システムモニター</h2>
      
      {cpuUsage && (
        <div className="metric">
          <h3>CPU使用率</h3>
          <p>{cpuUsage.usage_percent}%</p>
          <p>コア数: {cpuUsage.cpu_count}</p>
        </div>
      )}

      {memoryUsage && (
        <div className="metric">
          <h3>メモリ使用率</h3>
          <p>{memoryUsage.usage_percent}%</p>
          <p>使用中: {memoryUsage.used_gb} GB / {memoryUsage.total_gb} GB</p>
        </div>
      )}

      <div className="ec2-instances">
        <h3>EC2インスタンス</h3>
        {ec2Instances.map(instance => (
          <div key={instance.instance_id} className="instance">
            <p>ID: {instance.instance_id}</p>
            <p>タイプ: {instance.instance_type}</p>
            <p>状態: {instance.state}</p>
            <p>IP: {instance.public_ip || instance.private_ip}</p>
          </div>
        ))}
      </div>
    </div>
  );
}

export default SystemMonitor;
```

## ALB環境での設定

### ALBリスナールール

MCPサーバーもALB経由でアクセスできるように設定：

**ルール（優先度: 3）:**
- IF: Path is `/mcp/*`
- THEN: Forward to `mcp-server-tg` (port 9000)

### フロントエンドの環境変数

ALB環境では、相対パスを使用：

```javascript
// 本番環境では相対パス
const MCP_URL = window.location.hostname === 'localhost' 
  ? 'http://localhost:9000' 
  : '/mcp';
```

## 必要なIAM権限

EC2/ECS環境でAWS情報を取得するには、以下の権限が必要：

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances",
        "s3:ListAllMyBuckets",
        "rds:DescribeDBInstances",
        "bedrock:InvokeModel"
      ],
      "Resource": "*"
    }
  ]
}
```

## トラブルシューティング

### MCPサーバーが起動しない

```bash
# ログを確認
docker-compose logs mcp-server

# コンテナを再起動
docker-compose restart mcp-server
```

### AWS情報が取得できない

```bash
# IAMロールを確認（EC2の場合）
curl http://169.254.169.254/latest/meta-data/iam/security-credentials/

# AWS認証情報を確認
docker-compose exec mcp-server env | grep AWS
```

### ポート9000が使用中

```bash
# ポートを確認
lsof -i :9000

# docker-compose.ymlでポートを変更
ports:
  - "9001:9000"
```

## まとめ

### サービス構成

```
bedrock-ui/
├── backend (FastAPI) - Port 8000
├── frontend (React) - Port 3000
└── mcp-server (FastAPI) - Port 9000
    ├── システム情報（CPU, メモリ, ディスク）
    └── AWS情報（EC2, S3, RDS）
```

### アクセスURL

**ローカル開発:**
- Backend: http://localhost:8000
- Frontend: http://localhost:3000
- MCP Server: http://localhost:9000

**ALB環境:**
- Frontend: http://your-alb.com/
- Backend API: http://your-alb.com/api/*
- MCP Server: http://your-alb.com/mcp/*

これで、bedrock-uiからシステム情報とAWS情報をリアルタイムで監視できます！🎉
