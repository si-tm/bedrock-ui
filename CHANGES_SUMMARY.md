# 500エラー対処 - 変更内容サマリー

## 実施した変更

### 1. `docker-compose.yml` の修正
**変更内容:**
- デフォルトの `AWS_REGION` を `us-east-1` から `ap-northeast-1` に変更

**変更箇所:**
```yaml
# 変更前
- AWS_REGION=${AWS_REGION:-us-east-1}

# 変更後
- AWS_REGION=${AWS_REGION:-ap-northeast-1}
```

**理由:**
東京リージョン（ap-northeast-1）でBedrockを使用しているため、リージョン設定が一致していないとValidationExceptionが発生します。

---

### 2. `.env.production` の作成
**新規ファイル:** `.env.production`

**内容:**
```bash
# AWS設定 - EC2/ECS本番環境用
AWS_REGION=ap-northeast-1

# EC2/ECSではIAMロールから自動取得されるため、以下は不要
# AWS_ACCESS_KEY_ID=
# AWS_SECRET_ACCESS_KEY=

# フロントエンド設定（ALB環境では不要）
# REACT_APP_API_URL=
```

**用途:**
EC2上で本番環境を起動する際に使用する環境変数ファイル

---

### 3. `deploy-ec2.sh` の作成
**新規ファイル:** `deploy-ec2.sh`

**機能:**
- `.env`ファイルの自動生成
- IAMロールのチェック
- Docker コンテナのビルドと起動
- ヘルスチェックの自動実行
- Bedrock接続テスト

**使用方法:**
```bash
chmod +x deploy-ec2.sh
./deploy-ec2.sh
```

---

### 4. `diagnose.sh` の作成
**新規ファイル:** `diagnose.sh`

**機能:**
- AWS_REGION設定の確認
- IAMロールの確認
- Dockerコンテナの状態確認
- バックエンドヘルスチェック
- Bedrockクライアント初期化確認
- エラーログの抽出
- AWS CLI経由でのBedrockアクセステスト

**使用方法:**
```bash
chmod +x diagnose.sh
./diagnose.sh
```

---

### 5. `EC2_500_ERROR_FIX.md` の作成
**新規ファイル:** `EC2_500_ERROR_FIX.md`

**内容:**
- 500エラーの原因と対処法の詳細ガイド
- デバッグ手順
- よくある問題の解決方法
- 診断スクリプト

---

### 6. `QUICKFIX.md` の作成
**新規ファイル:** `QUICKFIX.md`

**内容:**
- 5分でできるクイックフィックス手順
- 問題別の対処法
- よくある質問

---

### 7. `setup-permissions.sh` の作成
**新規ファイル:** `setup-permissions.sh`

**機能:**
スクリプトファイルに実行権限を一括付与

**使用方法:**
```bash
bash setup-permissions.sh
```

---

## EC2での実行手順

### ステップ1: EC2にSSH接続
```bash
ssh -i your-key.pem ec2-user@your-ec2-ip
cd bedrock-ui
```

### ステップ2: 最新のコードをpull（Gitを使用している場合）
```bash
git pull origin main
```

### ステップ3: スクリプトに実行権限を付与
```bash
bash setup-permissions.sh
```

### ステップ4: 診断を実行
```bash
./diagnose.sh
```

### ステップ5: 問題を修正

#### 問題A: AWS_REGIONが間違っている
→ すでに `docker-compose.yml` を修正済みなので、コンテナを再起動するだけでOK
```bash
docker-compose down
docker-compose up -d
```

#### 問題B: IAMロールがない
1. AWSコンソール → EC2 → インスタンス選択
2. アクション → セキュリティ → IAMロールを変更
3. `bedrock-ui-ec2-role` を選択

```bash
docker-compose restart backend
```

#### 問題C: Bedrock Model Accessが無効
1. AWSコンソール → Amazon Bedrock（ap-northeast-1）
2. Model access → Manage model access
3. Claude 3 Sonnet にチェック → Submit

```bash
docker-compose restart backend
```

### ステップ6: 再度診断を実行
```bash
./diagnose.sh
```

すべて ✓ になるまで修正を繰り返す

### ステップ7: ブラウザでテスト
ALB URL（`http://your-alb-dns-name`）にアクセスしてチャットを送信

---

## 期待される結果

### 診断スクリプトの出力（成功時）
```
==========================================
Bedrock UI 診断スクリプト
==========================================

1. AWS_REGION設定の確認:
   ✓ AWS_REGION: ap-northeast-1
   ✓ docker-compose.yml のデフォルト: ap-northeast-1

2. IAMロールの確認:
   ✓ IAMロール: bedrock-ui-ec2-role
   ✓ 認証情報を取得できました

3. Dockerコンテナの状態:
   ✓ バックエンドコンテナ: 起動中

4. バックエンドのヘルスチェック:
   ✓ バックエンドは正常に応答しています

5. Bedrockクライアントの初期化:
   ✓ Bedrockクライアント: 初期化済み
   ✓ 使用リージョン: ap-northeast-1

6. 最新のエラーログ:
   ✓ エラーログはありません

7. Bedrock初期化ログ:
   ✓ 初期化成功

8. AWS CLI経由でBedrockアクセステスト:
   ✓ Bedrockへの直接アクセス成功

==========================================
診断結果サマリー
==========================================
✓ すべての診断項目をパスしました！
```

---

## トラブルシューティング

問題が解決しない場合は、以下のコマンドで詳細ログを確認：

```bash
# バックエンドのログ
docker-compose logs backend --tail=100

# エラーのみ抽出
docker-compose logs backend | grep -E "(ERROR|Exception|✗)"

# Bedrock関連のログのみ
docker-compose logs backend | grep -i bedrock
```

---

## まとめ

**主な変更:**
1. ✅ `docker-compose.yml` のデフォルトリージョンを `ap-northeast-1` に変更
2. ✅ EC2用の環境変数ファイル（`.env.production`）を作成
3. ✅ デプロイスクリプト（`deploy-ec2.sh`）を作成
4. ✅ 診断スクリプト（`diagnose.sh`）を作成
5. ✅ 詳細なトラブルシューティングガイドを作成

**これらの変更により:**
- AWS_REGIONの設定ミスによる500エラーが解決
- 簡単にデプロイと診断ができるように改善
- 問題の原因を素早く特定できるように改善

**次のステップ:**
1. EC2にSSH接続
2. `./diagnose.sh` を実行して現在の状態を確認
3. 問題があれば修正
4. ALB経由でブラウザからアクセスしてテスト
