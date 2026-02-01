# 500エラー対処 - 完了レポート

## ✅ 実施した対処

### 1. 設定ファイルの修正

#### `docker-compose.yml`
- **変更内容**: デフォルトの `AWS_REGION` を `us-east-1` → `ap-northeast-1` に変更
- **理由**: 東京リージョン（ap-northeast-1）でBedrockを使用しているため

### 2. 新規作成したファイル

#### ① `.env.production`
- EC2/ECS本番環境用の環境変数ファイル
- `AWS_REGION=ap-northeast-1` を設定

#### ② `deploy-ec2.sh` (実行可能スクリプト)
- EC2上での自動デプロイスクリプト
- 以下の処理を自動化:
  - .envファイルの生成
  - IAMロールのチェック
  - Dockerコンテナのビルドと起動
  - ヘルスチェック
  - Bedrock接続テスト

#### ③ `diagnose.sh` (実行可能スクリプト)
- 包括的な診断スクリプト
- 以下を自動チェック:
  - AWS_REGION設定
  - IAMロールの有無
  - Dockerコンテナの状態
  - バックエンドヘルスチェック
  - Bedrockクライアント初期化
  - エラーログ
  - AWS CLI経由でのBedrockアクセス

#### ④ `EC2_500_ERROR_FIX.md`
- 完全なトラブルシューティングガイド
- 以下を含む:
  - 5つの主な原因と対処法
  - デバッグ手順
  - クイック診断スクリプト

#### ⑤ `QUICKFIX.md`
- 5分でできるクイックフィックスガイド
- 問題別の対処法
- よくある質問

#### ⑥ `setup-permissions.sh`
- スクリプトファイルに実行権限を一括付与

#### ⑦ `CHANGES_SUMMARY.md`
- 変更内容の詳細サマリー
- EC2での実行手順

---

## 🎯 500エラーの原因と解決策

### 最も可能性が高い原因（優先順位順）

1. **AWS_REGIONの設定ミス** ✅ **修正済み**
   - 症状: ValidationException または EndpointConnectionError
   - 原因: `us-east-1` で設定されていた
   - 解決: `ap-northeast-1` に変更

2. **IAMロールがアタッチされていない**
   - 症状: Bedrockクライアントの初期化失敗
   - 解決: EC2コンソールでIAMロールをアタッチ

3. **Bedrock Model Accessが無効**
   - 症状: ResourceNotFoundException
   - 解決: AWSコンソールでModel Accessを有効化

4. **IAMロールに権限がない**
   - 症状: AccessDeniedException
   - 解決: IAMロールに `bedrock:InvokeModel` 権限を追加

---

## 📋 EC2での実行手順

### ステップ1: SSH接続
```bash
ssh -i your-key.pem ec2-user@your-ec2-ip
cd bedrock-ui
```

### ステップ2: 最新のコードを取得（Gitを使用している場合）
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

この診断スクリプトが自動的に以下を確認します：
- ✅ AWS_REGION設定
- ✅ IAMロール
- ✅ Dockerコンテナの状態
- ✅ Bedrockクライアント初期化
- ✅ エラーログ
- ✅ Bedrockへの接続

### ステップ5: 問題があれば修正

診断結果に応じて、以下のいずれかを実行：

#### ケースA: AWS_REGIONのみ問題
```bash
# すでに修正済みなので、再起動のみ
docker-compose down
docker-compose up -d
```

#### ケースB: IAMロールがない
1. AWSコンソール → EC2 → インスタンス選択
2. アクション → セキュリティ → IAMロールを変更
3. `bedrock-ui-ec2-role` を選択
4. コンテナ再起動:
```bash
docker-compose restart backend
```

#### ケースC: Bedrock Model Accessが無効
1. AWSコンソール → Amazon Bedrock（ap-northeast-1リージョン）
2. Model access → Manage model access
3. Claude 3 Sonnet にチェック
4. Submit
5. 数分待ってから:
```bash
docker-compose restart backend
```

### ステップ6: 再診断
```bash
./diagnose.sh
```

すべて ✓ になるまで修正を繰り返します。

### ステップ7: ブラウザでテスト
ALB URL (`http://your-alb-dns-name`) にアクセスしてチャットを送信

---

## 🔍 期待される結果

### 診断成功時の出力
```
==========================================
診断結果サマリー
==========================================
✓ すべての診断項目をパスしました！

ALB経由でアクセスしてチャット機能をテストしてください
```

### バックエンドログ（正常時）
```
Initializing Bedrock client in region: ap-northeast-1
✓ Bedrock client initialized successfully
```

### ヘルスチェック（正常時）
```bash
curl http://localhost:8000/

{
  "message": "Bedrock UI API is running",
  "region": "ap-northeast-1",
  "bedrock_client": "initialized"
}
```

---

## 📚 参考ドキュメント

- `QUICKFIX.md` - 5分でできるクイックフィックス
- `EC2_500_ERROR_FIX.md` - 詳細なトラブルシューティング
- `CHANGES_SUMMARY.md` - 変更内容の詳細

---

## 🆘 トラブルシューティング

問題が解決しない場合は、以下のコマンドでログを確認：

```bash
# バックエンドの詳細ログ
docker-compose logs backend --tail=100

# エラーのみ抽出
docker-compose logs backend | grep -E "(ERROR|Exception|✗)"

# Bedrock関連のログ
docker-compose logs backend | grep -i bedrock

# リアルタイムでログを監視
docker-compose logs -f backend
```

---

## ✨ まとめ

### 実施した対処
1. ✅ `docker-compose.yml` のリージョン設定を修正
2. ✅ EC2用の環境変数ファイルを作成
3. ✅ 自動デプロイスクリプトを作成
4. ✅ 自動診断スクリプトを作成
5. ✅ 詳細なトラブルシューティングガイドを作成

### これにより解決される問題
- ✅ AWS_REGIONの設定ミスによる500エラー
- ✅ 環境構築の簡素化
- ✅ 問題の迅速な診断と解決

### 次のアクション
1. EC2にSSH接続
2. `./diagnose.sh` を実行
3. 問題があれば修正
4. ALB経由でテスト

すべての対処が完了しました！🎉
