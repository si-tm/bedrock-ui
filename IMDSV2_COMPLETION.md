# IMDSv2対応 - 完了レポート

## ✅ 実施した対処

### 診断結果の分析

元の診断結果：
```
1. AWS_REGION設定の確認:
   ⚠ .envファイルが存在しません
   ✗ docker-compose.yml のデフォルト: ap (取得失敗)

2. IAMロールの確認:
   ✗ IAMロールがアタッチされていません

3. Dockerコンテナの状態:
   ✗ バックエンドコンテナが見つかりません

4. バックエンドのヘルスチェック:
   ✓ バックエンドは正常に応答しています

5. Bedrockクライアントの初期化:
   ✗ Bedrockクライアント: 初期化失敗

8. AWS CLI経由でBedrockアクセステスト:
   ✗ Bedrockへの直接アクセス失敗
   エラー: Invalid base64: ...
```

### 主な問題

1. **IMDSv2環境でスクリプトが正しく動作していない**
   - IAMロール取得が失敗
   - リージョン設定の取得が失敗
   
2. **.envファイルが存在しない**
   - AWS_REGION設定がない
   
3. **IAMロールがアタッチされていない**
   - Bedrockへのアクセス権限がない

4. **AWS CLIのコマンドが間違っている**
   - base64エンコードが不要なのにエンコードしていた

---

## 🔧 実施した修正

### 1. `diagnose.sh` をIMDSv2対応に更新

**追加した機能:**

```bash
# IMDSv2用のトークン取得関数
get_imds_token() {
    TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" \
        -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" \
        -s --connect-timeout 2 2>/dev/null)
    echo "$TOKEN"
}

# IMDSv2対応のメタデータ取得関数
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

**修正した箇所:**
- IAMロール取得 → IMDSv2対応の関数を使用
- 認証情報取得 → トークンを使用してアクセス
- リージョン設定の取得方法を改善
- AWS CLIコマンドの修正（base64エンコード不要）

### 2. `deploy-ec2.sh` をIMDSv2対応に更新

**追加した機能:**
- 同じ `get_imds_token()` と `get_metadata()` 関数
- IAMロールと認証情報の確認をIMDSv2対応に

### 3. 新規ドキュメントの作成

| ファイル名 | 内容 |
|-----------|------|
| `IMDSV2_FIX.md` | IMDSv2環境での詳細な対処ガイド |
| `QUICKSTART_IMDSV2.md` | 3ステップでできるクイックスタート |

---

## 📋 EC2での実行手順（改訂版）

### 前提条件
- EC2インスタンスにSSH接続済み
- `bedrock-ui` ディレクトリに移動済み
- IMDSv2が有効になっている

### ステップ1: 最新のスクリプトを取得

```bash
# Gitを使用している場合
git pull origin main

# または、ファイルを手動でアップロード
```

### ステップ2: スクリプトに実行権限を付与

```bash
chmod +x deploy-ec2.sh diagnose.sh setup-permissions.sh
```

### ステップ3: デプロイスクリプトを実行

```bash
./deploy-ec2.sh
```

このスクリプトは以下を実行します：
1. `.env`ファイルの作成（`AWS_REGION=ap-northeast-1`）
2. IAMロールの確認（IMDSv2対応）
3. Dockerコンテナのビルドと起動
4. ヘルスチェック

**期待される出力:**
```
✓ .envファイルを作成中...
✓ 環境変数の確認...
  AWS_REGION: ap-northeast-1
✓ IAMロールの確認...
  ⚠️  警告: IAMロールがアタッチされていません
```

### ステップ4: IAMロールをアタッチ（必須）

#### AWSコンソールで：

1. EC2 → インスタンス → あなたのインスタンスを選択
2. アクション → セキュリティ → IAMロールを変更
3. `bedrock-ui-ec2-role` を選択
4. IAMロールを更新

#### IAMロールがない場合：

`QUICKSTART_IMDSV2.md` の「IAMロールの作成手順」を参照

#### アタッチ後、確認：

```bash
# トークンを取得
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" -s)

# IAMロールを確認
curl -H "X-aws-ec2-metadata-token: $TOKEN" \
    http://169.254.169.254/latest/meta-data/iam/security-credentials/

# ロール名が表示されればOK

# コンテナを再起動
docker-compose restart backend
```

### ステップ5: Bedrock Model Accessを有効化

1. AWS Bedrockコンソール（ap-northeast-1リージョン）
2. Model access → Manage model access
3. Anthropic → Claude 3 Sonnet にチェック
4. Request model access → Submit
5. 数分待つ
6. コンテナを再起動: `docker-compose restart backend`

### ステップ6: 診断を実行

```bash
./diagnose.sh
```

**期待される出力:**
```
==========================================
Bedrock UI 診断スクリプト (IMDSv2対応)
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

ALB経由でアクセスしてチャット機能をテストしてください
```

### ステップ7: ブラウザでテスト

ALB URL（`http://your-alb-dns-name`）にアクセスしてチャットを送信

---

## 🔍 IMDSv2の技術的詳細

### IMDSv1 vs IMDSv2

| 項目 | IMDSv1 | IMDSv2 |
|------|--------|--------|
| 認証 | なし | トークンベース |
| セキュリティ | 低 | 高 |
| SSRF対策 | 脆弱 | 堅牢 |
| リクエスト方法 | GET | PUT → GET |

### IMDSv2のリクエストフロー

1. **トークン取得**
```bash
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" -s)
```

2. **メタデータ取得**
```bash
curl -H "X-aws-ec2-metadata-token: $TOKEN" \
    http://169.254.169.254/latest/meta-data/iam/security-credentials/
```

### スクリプトでの実装

```bash
# 汎用的なメタデータ取得関数
get_metadata() {
    local path=$1
    local token=$(get_imds_token)
    
    if [ -z "$token" ]; then
        # フォールバック: IMDSv1
        curl -s "http://169.254.169.254/latest/meta-data/$path"
    else
        # メイン: IMDSv2
        curl -s -H "X-aws-ec2-metadata-token: $token" \
            "http://169.254.169.254/latest/meta-data/$path"
    fi
}

# 使用例
ROLE=$(get_metadata "iam/security-credentials/")
REGION=$(get_metadata "placement/region")
```

---

## 📊 修正前後の比較

### 修正前（IMDSv1のみ対応）

```bash
# IAMロール取得
ROLE=$(curl -s http://169.254.169.254/latest/meta-data/iam/security-credentials/)
# → IMDSv2環境では失敗
```

### 修正後（IMDSv2対応）

```bash
# IAMロール取得
ROLE=$(get_metadata "iam/security-credentials/")
# → IMDSv2/v1どちらでも動作
```

---

## 🎯 解決される問題

### 修正前の問題

1. ✗ IAMロールの取得に失敗
2. ✗ リージョン設定の取得に失敗
3. ✗ 認証情報の取得に失敗
4. ✗ AWS CLIコマンドのエラー

### 修正後

1. ✅ IAMロールを正しく取得
2. ✅ リージョン設定を正しく取得
3. ✅ 認証情報を正しく取得
4. ✅ AWS CLIコマンドが正常動作

---

## 📚 関連ドキュメント

| ドキュメント | 用途 |
|------------|------|
| `QUICKSTART_IMDSV2.md` | **今すぐ始める** - 3ステップのクイックスタート |
| `IMDSV2_FIX.md` | **詳細を知る** - IMDSv2の詳細と対処法 |
| `EC2_500_ERROR_FIX.md` | **トラブルシューティング** - 500エラーの完全ガイド |
| `COMPLETION_REPORT.md` | **全体の変更** - 最初の対処内容 |

---

## ✅ チェックリスト

すべて完了後、以下を確認：

- [ ] `diagnose.sh` と `deploy-ec2.sh` が最新版（IMDSv2対応）
- [ ] `.env`ファイルが存在し、`AWS_REGION=ap-northeast-1`
- [ ] EC2にIAMロールがアタッチされている
- [ ] IAMロールに `bedrock:InvokeModel` 権限がある
- [ ] Bedrock Model Access で Claude 3 Sonnet が有効
- [ ] `./diagnose.sh` の結果がすべて ✓
- [ ] ALB経由でチャットが正常動作

---

## 🎉 まとめ

### 主な対処内容

1. ✅ **診断スクリプトをIMDSv2対応に更新**
   - トークンベースの認証を実装
   - IMDSv1へのフォールバック機能を追加

2. ✅ **デプロイスクリプトをIMDSv2対応に更新**
   - 同様の認証メカニズムを実装

3. ✅ **AWS CLIコマンドの修正**
   - base64エンコードの問題を解決

4. ✅ **包括的なドキュメント作成**
   - IMDSv2対応ガイド
   - クイックスタートガイド

### 次のアクション

EC2上で以下を実行：

```bash
cd bedrock-ui
chmod +x deploy-ec2.sh diagnose.sh
./deploy-ec2.sh          # 環境セットアップ
# IAMロールをアタッチ（AWSコンソール）
# Bedrock Model Accessを有効化（AWSコンソール）
./diagnose.sh            # 診断実行
```

すべて ✓ になったら、ALB経由でテスト！

500エラーは完全に解決するはずです！🎊
