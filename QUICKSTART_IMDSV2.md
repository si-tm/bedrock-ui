# 500エラー対処 - IMDSv2対応クイックスタート

## 🎯 現在の状況

診断結果から以下の問題が検出されています：

1. ❌ IAMロールがアタッチされていない
2. ⚠️  .envファイルが存在しない
3. ❌ Bedrockクライアントの初期化失敗

## ⚡ 3ステップで解決（5分）

### ステップ1: 環境をセットアップ（1分）

```bash
# EC2にSSH接続している状態で実行
cd bedrock-ui

# デプロイスクリプトを実行
chmod +x deploy-ec2.sh diagnose.sh
./deploy-ec2.sh
```

これで以下が自動的に完了します：
- ✅ `.env`ファイルの作成（AWS_REGION=ap-northeast-1）
- ✅ Dockerコンテナのビルドと起動
- ✅ ヘルスチェック

### ステップ2: IAMロールをアタッチ（2分）

**現在、IAMロールがアタッチされていないため、この手順は必須です。**

#### 方法A: AWSコンソール（推奨）

1. EC2コンソールを開く: https://console.aws.amazon.com/ec2/
2. あなたのインスタンスを選択
3. **アクション** → **セキュリティ** → **IAMロールを変更**
4. `bedrock-ui-ec2-role` を選択（ない場合は後述の手順で作成）
5. **IAMロールを更新** をクリック

#### 方法B: AWS CLI

```bash
# ローカルマシンから実行（EC2上ではない）
INSTANCE_ID="i-xxxxxxxxxxxxxxxxx"  # あなたのインスタンスID

aws ec2 associate-iam-instance-profile \
  --instance-id $INSTANCE_ID \
  --iam-instance-profile Name=bedrock-ui-ec2-instance-profile
```

#### IAMロールがない場合（作成手順）

1. IAMコンソール: https://console.aws.amazon.com/iam/
2. ロール → ロールを作成
3. 信頼されたエンティティ: **AWS サービス** → **EC2**
4. 以下のポリシーを追加:

**インラインポリシー（JSON）:**
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

5. ロール名: `bedrock-ui-ec2-role`
6. ロールを作成
7. EC2インスタンスにアタッチ（方法A または 方法B）

#### アタッチ後

```bash
# EC2で確認
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" -s)

curl -H "X-aws-ec2-metadata-token: $TOKEN" \
    http://169.254.169.254/latest/meta-data/iam/security-credentials/

# ロール名が表示されればOK

# コンテナを再起動
docker-compose restart backend
```

### ステップ3: Bedrock Model Accessを有効化（2分）

1. **AWS Bedrockコンソールを開く**
   - https://console.aws.amazon.com/bedrock/
   - **重要**: リージョンを **東京（ap-northeast-1）** に変更

2. **Model accessを開く**
   - 左メニュー → **Model access**

3. **モデルアクセスを管理**
   - 「**Manage model access**」をクリック

4. **Claude 3 Sonnetを有効化**
   - **Anthropic** セクションを探す
   - **Claude 3 Sonnet** にチェック
   - 「**Request model access**」をクリック
   - 「**Submit**」をクリック

5. **ステータスを確認**
   - 数分待つ
   - ステータスが「**Available**」になるのを確認

6. **コンテナを再起動**
```bash
docker-compose restart backend
```

---

## ✅ 確認

すべての手順完了後、診断を実行：

```bash
./diagnose.sh
```

**期待される出力:**
```
==========================================
診断結果サマリー
==========================================
✓ すべての診断項目をパスしました！

ALB経由でアクセスしてチャット機能をテストしてください
```

---

## 🌐 テスト

ALB URL（`http://your-alb-dns-name`）にアクセスして、チャットメッセージを送信してください。

500エラーが解消され、Claudeからの応答が返るはずです！

---

## 🔍 まだエラーが出る場合

### ログを確認

```bash
# バックエンドのログ
docker-compose logs backend --tail=50

# Bedrockに関するログのみ
docker-compose logs backend | grep -i bedrock

# エラーのみ
docker-compose logs backend | grep -E "(ERROR|Exception)"
```

### よくあるエラーと解決法

#### エラー: `AccessDeniedException`
**原因:** IAMロールに権限がない  
**解決:** ステップ2のIAMポリシーを確認

#### エラー: `ResourceNotFoundException`
**原因:** Bedrock Model Accessが無効  
**解決:** ステップ3を再度実行

#### エラー: `ValidationException: Cross region inference`
**原因:** リージョンの設定ミス  
**解決:**
```bash
cat .env
# AWS_REGION=ap-northeast-1 になっているか確認

# 違う場合は修正
echo "AWS_REGION=ap-northeast-1" > .env
docker-compose restart backend
```

---

## 📚 詳細なドキュメント

- `IMDSV2_FIX.md` - IMDSv2環境での詳細な対処法
- `EC2_500_ERROR_FIX.md` - 完全なトラブルシューティングガイド
- `QUICKFIX.md` - クイックフィックスガイド

---

## 🆘 サポート

問題が解決しない場合は、以下の情報を収集：

```bash
# 診断結果
./diagnose.sh > diagnosis.txt

# ログ
docker-compose logs backend --tail=100 > backend.log

# 環境設定
cat .env > config.txt
cat docker-compose.yml >> config.txt
```

これらのファイルを確認して、問題の原因を特定できます。
