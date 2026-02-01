# IMDSv2環境での対処ガイド

## 🔒 IMDSv2とは

IMDSv2 (Instance Metadata Service Version 2) は、EC2インスタンスのメタデータサービスのセキュアなバージョンです。

従来のIMDSv1との違い：
- トークンベースの認証が必須
- SSRFなどの攻撃に対してより安全

## 🚨 現在の診断結果

診断スクリプトの出力から、以下の問題が検出されています：

### 問題1: .envファイルが存在しない ⚠️
```
✗ .envファイルが存在しません
```

### 問題2: IAMロールがアタッチされていない ❌
```
✗ IAMロールがアタッチされていません
   EC2コンソールでIAMロールをアタッチしてください
```

### 問題3: Bedrockクライアントの初期化失敗 ❌
```
✗ Bedrockクライアント: 初期化失敗
```

## ⚡ クイックフィックス

### ステップ1: deploy-ec2.shを実行して環境をセットアップ

```bash
# スクリプトに実行権限を付与（まだの場合）
chmod +x deploy-ec2.sh diagnose.sh

# デプロイスクリプトを実行
./deploy-ec2.sh
```

このスクリプトは以下を自動的に行います：
- ✅ `.env`ファイルの作成（AWS_REGION=ap-northeast-1）
- ✅ IAMロールの確認（IMDSv2対応）
- ✅ Dockerコンテナのビルドと起動
- ✅ ヘルスチェックの実行

### ステップ2: IAMロールをアタッチ（必須）

現在IAMロールがアタッチされていないため、以下の手順で追加してください：

#### AWSコンソールでの手順：

1. **EC2コンソールを開く**
   - https://console.aws.amazon.com/ec2/

2. **インスタンスを選択**
   - あなたのEC2インスタンスを選択

3. **IAMロールを変更**
   - アクション → セキュリティ → IAMロールを変更

4. **ロールを選択**
   - `bedrock-ui-ec2-role` を選択
   - もしロールがない場合は、以下のポリシーで作成：

#### IAMロールのポリシー（必要な場合）：

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

信頼関係：
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

5. **IAMロールを更新**
   - 「IAMロールを更新」をクリック

6. **コンテナを再起動**
```bash
docker-compose restart backend
```

### ステップ3: Bedrock Model Accessを有効化

1. **AWS Bedrockコンソールを開く**
   - https://console.aws.amazon.com/bedrock/
   - **重要**: リージョンを `ap-northeast-1` (東京) に変更

2. **Model accessを開く**
   - 左メニュー → Model access

3. **モデルアクセスを管理**
   - 「Manage model access」をクリック

4. **Claude 3 Sonnetを有効化**
   - Anthropic の **Claude 3 Sonnet** にチェック
   - 「Request model access」をクリック
   - 「Submit」をクリック

5. **数分待つ**
   - Model accessのステータスが「Available」になるまで待つ

6. **コンテナを再起動**
```bash
docker-compose restart backend
```

### ステップ4: 診断を実行

```bash
./diagnose.sh
```

期待される出力（すべて ✓ になるまで繰り返す）：

```
==========================================
診断結果サマリー
==========================================
✓ すべての診断項目をパスしました！

ALB経由でアクセスしてチャット機能をテストしてください
```

### ステップ5: ブラウザでテスト

ALB URL（`http://your-alb-dns-name`）にアクセスしてチャットを送信

---

## 🔍 IMDSv2対応の詳細

### スクリプトの変更点

診断スクリプトとデプロイスクリプトは、IMDSv2に対応するために以下の変更を行いました：

#### トークン取得関数
```bash
get_imds_token() {
    TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" \
        -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" \
        -s --connect-timeout 2 2>/dev/null)
    echo "$TOKEN"
}
```

#### メタデータ取得関数（IMDSv2対応）
```bash
get_metadata() {
    local path=$1
    local token=$(get_imds_token)
    
    if [ -z "$token" ]; then
        # IMDSv2が失敗した場合、IMDSv1で試行
        curl -s --connect-timeout 2 "http://169.254.169.254/latest/meta-data/$path" 2>/dev/null
    else
        # IMDSv2でアクセス
        curl -s --connect-timeout 2 \
            -H "X-aws-ec2-metadata-token: $token" \
            "http://169.254.169.254/latest/meta-data/$path" 2>/dev/null
    fi
}
```

#### 使用例
```bash
# IAMロール名を取得
ROLE=$(get_metadata "iam/security-credentials/")

# 認証情報を取得
TOKEN=$(get_imds_token)
CREDS=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
    "http://169.254.169.254/latest/meta-data/iam/security-credentials/$ROLE")
```

---

## 📋 トラブルシューティング

### Q: deploy-ec2.shを実行したが、まだエラーが出る

**A:** 以下を確認してください：

1. **IAMロールが正しくアタッチされているか**
```bash
# トークンを取得
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" -s)

# IAMロールを確認
curl -H "X-aws-ec2-metadata-token: $TOKEN" \
    http://169.254.169.254/latest/meta-data/iam/security-credentials/
```

ロール名が表示されればOK

2. **Bedrock Model Accessが有効化されているか**
```bash
aws bedrock list-foundation-models \
  --region ap-northeast-1 \
  --query 'modelSummaries[?contains(modelId, `claude-3-sonnet`)].modelId'
```

モデルIDが表示されればOK

3. **コンテナのログを確認**
```bash
docker-compose logs backend | grep -E "(Bedrock|ERROR|✓|✗)"
```

### Q: AWS CLIでのBedrockテストが失敗する

**診断結果:**
```
✗ Bedrockへの直接アクセス失敗
   エラー: Invalid base64: ...
```

**A:** これは診断スクリプトのバグでした。IMDSv2対応版では修正済みです。
最新の診断スクリプトを使用してください：

```bash
./diagnose.sh
```

### Q: Bedrockクライアントの初期化に失敗する

**A:** 以下を順番に確認：

1. **AWS_REGIONが正しいか**
```bash
cat .env | grep AWS_REGION
# 出力: AWS_REGION=ap-northeast-1
```

2. **IAMロールに権限があるか**
```bash
# ロール名を取得
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" -s)
ROLE=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" \
    http://169.254.169.254/latest/meta-data/iam/security-credentials/)

# IAMコンソールでこのロールのポリシーを確認
echo "IAMロール: $ROLE"
```

3. **コンテナを再起動**
```bash
docker-compose restart backend
docker-compose logs backend | grep Bedrock
```

---

## ✅ 最終チェックリスト

すべて完了したら、以下をチェック：

- [ ] `.env`ファイルが存在し、`AWS_REGION=ap-northeast-1` が設定されている
- [ ] EC2にIAMロールがアタッチされている
- [ ] IAMロールに `bedrock:InvokeModel` 権限がある
- [ ] Bedrock Model Access で Claude 3 Sonnet が有効化されている
- [ ] `./diagnose.sh` の結果がすべて ✓
- [ ] `curl http://localhost:8000/` で `"bedrock_client": "initialized"` が返る
- [ ] ALB経由でチャットが送信できる

---

## 🎯 まとめ

**主な変更点:**
1. ✅ 診断スクリプトをIMDSv2対応に更新
2. ✅ デプロイスクリプトをIMDSv2対応に更新
3. ✅ AWS CLI のBedrockテストコマンドを修正

**次のアクション:**
1. `./deploy-ec2.sh` を実行して環境をセットアップ
2. EC2コンソールでIAMロールをアタッチ
3. Bedrock Model Accessを有効化
4. `./diagnose.sh` で確認
5. ALB経由でテスト

これで500エラーは解決するはずです！🎉
