# EC2での500エラー対処ガイド

## 問題
ALB経由でアクセスした際、チャット送信時に以下のエラーが発生：
```
Error sending message: AxiosError: Request failed with status code 500
```

## 最も可能性の高い原因と対処法

### 1. AWS_REGIONの設定ミス（最重要！）

**症状:**
- チャット送信時に500エラー
- バックエンドログに `ValidationException` または `EndpointConnectionError`

**原因:**
`docker-compose.yml` のデフォルトリージョンが `us-east-1` になっている

**対処法:**

```bash
# EC2にSSH接続
ssh -i your-key.pem ec2-user@your-ec2-ip

# bedrock-uiディレクトリに移動
cd bedrock-ui

# .envファイルを作成（存在しない場合）
cat > .env << 'EOF'
AWS_REGION=ap-northeast-1
EOF

# docker-compose.ymlの確認
grep "AWS_REGION" docker-compose.yml
# 出力: - AWS_REGION=${AWS_REGION:-ap-northeast-1}
# ↑ ap-northeast-1 になっていることを確認

# コンテナを再起動
docker-compose down
docker-compose up -d

# ログを確認
docker-compose logs backend | grep -E "(region|Region|REGION)"
```

**期待される出力:**
```
Initializing Bedrock client in region: ap-northeast-1
✓ Bedrock client initialized successfully
```

---

### 2. IAMロールがアタッチされていない

**症状:**
- バックエンドログに `Failed to initialize Bedrock client`
- `/` エンドポイントで `bedrock_client: "not initialized"`

**確認方法:**

```bash
# EC2インスタンス上で実行
curl http://169.254.169.254/latest/meta-data/iam/security-credentials/

# 何も表示されない場合 → IAMロールがアタッチされていない
# ロール名が表示される場合 → OK
```

**対処法:**

AWSコンソールで：
1. EC2 → インスタンス → あなたのインスタンスを選択
2. アクション → セキュリティ → IAMロールを変更
3. `bedrock-ui-ec2-role` を選択
4. IAMロールを更新

コンテナを再起動：
```bash
docker-compose restart backend
docker-compose logs backend | grep Bedrock
```

---

### 3. IAMロールに権限がない

**症状:**
- バックエンドログに `AccessDeniedException`
- `bedrock_client` は初期化されているが、チャット送信時にエラー

**確認方法:**

```bash
# EC2上でAWS CLIを使用してBedrockをテスト
aws bedrock-runtime invoke-model \
  --model-id anthropic.claude-3-sonnet-20240229-v1:0 \
  --body '{"anthropic_version":"bedrock-2023-05-31","max_tokens":100,"messages":[{"role":"user","content":"Hello"}]}' \
  --region ap-northeast-1 \
  output.json

# 成功すれば権限OK
cat output.json

# AccessDeniedException が出る場合 → 権限不足
```

**対処法:**

IAMロールに以下のポリシーを追加：

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "bedrock:InvokeModel",
        "bedrock:InvokeModelWithResponseStream"
      ],
      "Resource": [
        "arn:aws:bedrock:ap-northeast-1::foundation-model/anthropic.claude-3-sonnet-20240229-v1:0"
      ]
    }
  ]
}
```

AWSコンソールで：
1. IAM → ロール → `bedrock-ui-ec2-role`
2. 許可を追加 → ポリシーをアタッチ
3. 上記のポリシーを作成してアタッチ

---

### 4. Bedrock Model Accessが有効化されていない

**症状:**
- バックエンドログに `ResourceNotFoundException` または `AccessDeniedException`
- 権限はあるのにモデルにアクセスできない

**確認方法:**

```bash
# 利用可能なモデルを確認
aws bedrock list-foundation-models \
  --region ap-northeast-1 \
  --query 'modelSummaries[?contains(modelId, `claude-3-sonnet`)].modelId'

# 空の配列 [] が返る場合 → Model Accessが無効
```

**対処法:**

AWSコンソールで：
1. Amazon Bedrock（ap-northeast-1リージョン）
2. 左メニュー → Model access
3. Manage model access をクリック
4. **Anthropic** の **Claude 3 Sonnet** にチェック
5. Request model access → Submit

数分後にアクセスが有効化されます。

---

### 5. クロスリージョンインファレンスの問題

**症状:**
- バックエンドログに `ValidationException: Cross region inference is not supported`

**原因:**
Claude 3 モデルを東京リージョン（ap-northeast-1）から呼び出そうとしているが、モデルが別のリージョンにのみ存在する

**対処法:**

`backend/main.py` を確認：

```python
# この行を確認
modelId='anthropic.claude-3-sonnet-20240229-v1:0'
```

東京リージョンでサポートされているモデルを使用：
- `anthropic.claude-3-sonnet-20240229-v1:0` ✓（東京リージョンで利用可能）
- `anthropic.claude-3-5-sonnet-20240620-v1:0`（新しいバージョン）

必要に応じてモデルIDを変更：

```bash
cd backend
# main.pyを編集してモデルIDを変更

# コンテナを再起動
cd ..
docker-compose restart backend
```

---

## 完全なデバッグ手順

### ステップ1: 環境変数の確認

```bash
# EC2上で実行
cd bedrock-ui

# .envファイルを確認
cat .env

# 期待される内容:
# AWS_REGION=ap-northeast-1

# コンテナ内の環境変数を確認
docker-compose exec backend env | grep AWS
```

### ステップ2: IAMロールの確認

```bash
# IAMロールがアタッチされているか確認
curl http://169.254.169.254/latest/meta-data/iam/security-credentials/

# ロール名が表示されればOK
```

### ステップ3: バックエンドログの確認

```bash
# リアルタイムでログを確認
docker-compose logs -f backend

# または最新50行を確認
docker-compose logs backend --tail=50

# エラーを検索
docker-compose logs backend | grep -E "(ERROR|Exception|✗)"
```

**期待されるログ:**
```
Initializing Bedrock client in region: ap-northeast-1
✓ Bedrock client initialized successfully
```

**問題があるログ:**
```
✗ Failed to initialize Bedrock client: ...
ERROR: AccessDeniedException: ...
ERROR: ResourceNotFoundException: ...
ERROR: ValidationException: Cross region inference is not supported
```

### ステップ4: ヘルスチェック

```bash
# バックエンドのヘルスチェック
curl http://localhost:8000/health

# ルートエンドポイント
curl http://localhost:8000/

# 期待される出力:
# {
#   "message": "Bedrock UI API is running",
#   "region": "ap-northeast-1",
#   "bedrock_client": "initialized"
# }
```

### ステップ5: チャットAPIのテスト

```bash
# チャットAPIを直接テスト
curl -X POST http://localhost:8000/api/chat \
  -H "Content-Type: application/json" \
  -d '{
    "message": "Hello",
    "conversation_history": []
  }'

# 成功すれば、Claudeからの応答が返る
# 失敗すれば、詳細なエラーメッセージが返る
```

### ステップ6: AWS CLIでBedrockをテスト

```bash
# EC2上でAWS CLIを使用してBedrockに直接アクセス
aws bedrock-runtime invoke-model \
  --model-id anthropic.claude-3-sonnet-20240229-v1:0 \
  --body '{"anthropic_version":"bedrock-2023-05-31","max_tokens":100,"messages":[{"role":"user","content":"Hello"}]}' \
  --region ap-northeast-1 \
  output.json

cat output.json

# 成功すれば、AWS認証とBedrock設定は正しい
# 失敗すれば、IAMロールまたはModel Accessに問題がある
```

---

## 修正後の確認手順

```bash
# 1. コンテナを再起動
docker-compose down
docker-compose up -d

# 2. ログを確認（初期化を確認）
docker-compose logs backend | grep -E "(Bedrock|✓|✗)"

# 期待される出力:
# ✓ Bedrock client initialized successfully

# 3. ヘルスチェック
curl http://localhost:8000/

# 4. ALB経由でブラウザからアクセス
# http://your-alb-dns-name

# 5. チャット機能をテスト
```

---

## クイック診断スクリプト

以下のスクリプトを実行して、すべての設定を確認：

```bash
#!/bin/bash
echo "=== Bedrock UI診断スクリプト ==="
echo ""

echo "1. AWS_REGION確認:"
source .env 2>/dev/null
echo "   ${AWS_REGION:-ap-northeast-1}"

echo ""
echo "2. IAMロール確認:"
ROLE=$(curl -s http://169.254.169.254/latest/meta-data/iam/security-credentials/)
if [ -z "$ROLE" ]; then
    echo "   ✗ IAMロールがアタッチされていません"
else
    echo "   ✓ $ROLE"
fi

echo ""
echo "3. バックエンド起動確認:"
if curl -s -f http://localhost:8000/health > /dev/null; then
    echo "   ✓ バックエンドは起動しています"
else
    echo "   ✗ バックエンドが起動していません"
fi

echo ""
echo "4. Bedrockクライアント確認:"
BEDROCK=$(curl -s http://localhost:8000/ | grep -o '"bedrock_client":"[^"]*"' | cut -d'"' -f4)
if [ "$BEDROCK" = "initialized" ]; then
    echo "   ✓ Bedrockクライアントは初期化されています"
else
    echo "   ✗ Bedrockクライアントの初期化に失敗"
fi

echo ""
echo "5. 最新のエラーログ:"
docker-compose logs backend --tail=10 | grep -E "(ERROR|Exception)"
```

このスクリプトを `diagnose.sh` として保存して実行：
```bash
chmod +x diagnose.sh
./diagnose.sh
```

---

## まとめ

**最も可能性が高い原因（優先順位順）:**

1. ✅ **AWS_REGIONの設定ミス** - `us-east-1` → `ap-northeast-1` に変更
2. ✅ **IAMロールがアタッチされていない** - EC2にIAMロールをアタッチ
3. ✅ **Bedrock Model Accessが無効** - AWSコンソールで有効化
4. ✅ **IAMロールに権限がない** - `bedrock:InvokeModel` 権限を追加

**すべての修正を適用した後:**
```bash
docker-compose down
docker-compose up -d
docker-compose logs backend | grep -E "(Bedrock|✓|✗|ERROR)"
```

問題が解決しない場合は、上記のログ出力を確認してください。
