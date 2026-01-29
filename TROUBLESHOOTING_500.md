# バックエンド500エラーのトラブルシューティング

## エラー内容
```
POST http://alb-hyakuzuka-891406204.ap-northeast-1.elb.amazonaws.com/api/chat 500 (Internal Server Error)
```

## 原因の確認方法

### 1. バックエンドのログを確認

**EC2の場合:**
```bash
# コンテナのログを確認
docker logs <backend-container-id>

# または
cd /path/to/bedrock-ui
docker-compose logs backend
```

**ECSの場合:**
```bash
# CloudWatch Logsで確認
aws logs tail /ecs/bedrock-ui-backend --follow --region ap-northeast-1
```

### 2. バックエンドの状態を確認

```bash
# ヘルスチェック
curl http://alb-hyakuzuka-891406204.ap-northeast-1.elb.amazonaws.com/health

# ルートエンドポイント
curl http://alb-hyakuzuka-891406204.ap-northeast-1.elb.amazonaws.com/
```

期待される出力:
```json
{
  "message": "Bedrock UI API is running",
  "region": "ap-northeast-1",
  "bedrock_client": "initialized"
}
```

## よくある原因と解決策

### 原因1: AWS認証情報がない

**症状:**
- ログに "Failed to initialize Bedrock client" が表示
- bedrock_client: "not initialized"

**解決策:**

**EC2の場合:**
```bash
# IAMロールがアタッチされているか確認
curl http://169.254.169.254/latest/meta-data/iam/security-credentials/

# 何も表示されない場合は、IAMロールをアタッチ
aws ec2 associate-iam-instance-profile \
  --instance-id i-xxxxx \
  --iam-instance-profile Name=bedrock-ui-ec2-profile
```

**ECSの場合:**
- タスク定義にtaskRoleArnが設定されているか確認
- タスクロールにbedrock:InvokeModel権限があるか確認

### 原因2: Bedrockモデルアクセスが有効化されていない

**症状:**
- ログに "ResourceNotFoundException" または "AccessDeniedException"

**解決策:**
1. AWSコンソール → Amazon Bedrock
2. 左メニュー → **Model access**
3. **Manage model access** をクリック
4. **Claude 3 Sonnet** にチェック
5. **Save changes**

```bash
# CLIで確認
aws bedrock list-foundation-models \
  --region ap-northeast-1 \
  --query 'modelSummaries[?contains(modelId, `claude-3-sonnet`)].modelId'
```

### 原因3: IAMロールに権限がない

**症状:**
- ログに "AccessDeniedException" が表示

**解決策:**

IAMロールに以下のポリシーを追加:

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
        "arn:aws:bedrock:ap-northeast-1::foundation-model/anthropic.claude-3-sonnet-20240229-v1:0"
      ]
    }
  ]
}
```

```bash
# ポリシーをアタッチ
aws iam put-role-policy \
  --role-name bedrock-ui-role \
  --policy-name BedrockInvokeModel \
  --policy-document file://bedrock-policy.json
```

### 原因4: リージョンが間違っている

**症状:**
- ログに "EndpointConnectionError" または "Could not connect to the endpoint URL"

**解決策:**

環境変数を確認:

**EC2の場合:**
```bash
# .envファイルを確認
cat .env
# AWS_REGION=ap-northeast-1 であることを確認

# コンテナを再起動
docker-compose restart backend
```

**ECSの場合:**
- タスク定義の環境変数を確認
- AWS_REGION=ap-northeast-1 に設定

### 原因5: モデルIDが間違っている

**症状:**
- ログに "ValidationException" が表示

**解決策:**

main.pyのモデルIDを確認:
```python
modelId='anthropic.claude-3-sonnet-20240229-v1:0'
```

利用可能なモデルを確認:
```bash
aws bedrock list-foundation-models \
  --region ap-northeast-1 \
  --by-provider anthropic
```

## デバッグ手順

### ステップ1: ログを確認

```bash
# リアルタイムでログを確認
docker-compose logs -f backend

# または
docker logs -f <container-id>
```

以下のようなログを探す:
```
ERROR: Failed to initialize Bedrock client: ...
ERROR: Error in chat endpoint: AccessDeniedException: ...
```

### ステップ2: 手動でAPIをテスト

```bash
# ヘルスチェック
curl http://localhost:8000/health

# チャットAPIをテスト
curl -X POST http://localhost:8000/api/chat \
  -H "Content-Type: application/json" \
  -d '{
    "message": "Hello",
    "conversation_history": []
  }'
```

### ステップ3: AWS認証を確認

```bash
# EC2の場合
curl http://169.254.169.254/latest/meta-data/iam/security-credentials/

# コンテナ内で確認
docker-compose exec backend env | grep AWS
```

### ステップ4: Bedrockに直接アクセスしてみる

```bash
# AWS CLIでBedrockをテスト
aws bedrock-runtime invoke-model \
  --model-id anthropic.claude-3-sonnet-20240229-v1:0 \
  --body '{"anthropic_version":"bedrock-2023-05-31","max_tokens":100,"messages":[{"role":"user","content":"Hello"}]}' \
  --region ap-northeast-1 \
  output.json

cat output.json
```

成功すれば、AWS認証とBedrock設定は正しい。

## 修正後の確認

1. **コンテナを再起動**
```bash
docker-compose restart backend
```

2. **ログを確認**
```bash
docker-compose logs backend | grep -E "(✓|✗|ERROR)"
```

期待される出力:
```
✓ Bedrock client initialized successfully
```

3. **フロントエンドから再テスト**

ブラウザで http://your-alb.com にアクセスして、チャットを試す。

## 最も可能性の高い原因

ALB環境で500エラーが出る場合、**最も多い原因は**:

1. ✅ **IAMロールがアタッチされていない** (60%)
2. ✅ **Bedrock Model Accessが有効化されていない** (30%)
3. ✅ **IAMロールに権限がない** (10%)

これらを順番に確認してください！

## まとめ

エラーログを確認すれば、正確な原因が分かります。

```bash
# このコマンドでログを確認
docker-compose logs backend --tail=50

# エラーメッセージをここに貼り付けてください
```
