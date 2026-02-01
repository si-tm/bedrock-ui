# EC2での500エラー - クイックフィックスガイド

## 🚨 問題
ALB経由でアクセスした際、チャット送信時に500エラーが発生

## ⚡ クイックフィックス（5分で解決）

### EC2にSSH接続
```bash
ssh -i your-key.pem ec2-user@your-ec2-ip
cd bedrock-ui
```

### ステップ1: 診断スクリプトを実行
```bash
chmod +x diagnose.sh
./diagnose.sh
```

このスクリプトが問題を自動検出します。

### ステップ2: 問題に応じた対処

#### 問題A: AWS_REGIONが間違っている
```bash
# .envファイルを作成
cat > .env << 'EOF'
AWS_REGION=ap-northeast-1
EOF

# コンテナを再起動
docker-compose down
docker-compose up -d
```

#### 問題B: IAMロールがない
1. AWSコンソール → EC2 → インスタンス選択
2. アクション → セキュリティ → IAMロールを変更
3. `bedrock-ui-ec2-role` を選択
4. 更新

```bash
# 再起動
docker-compose restart backend
```

#### 問題C: Bedrock Model Accessが無効
1. AWSコンソール → Amazon Bedrock（ap-northeast-1リージョン）
2. Model access → Manage model access
3. **Claude 3 Sonnet** にチェック
4. Submit

数分待ってから：
```bash
docker-compose restart backend
```

### ステップ3: 確認
```bash
# 診断スクリプトを再実行
./diagnose.sh

# すべて✓になるまで修正を繰り返す
```

### ステップ4: ブラウザでテスト
ALB URL（`http://your-alb-dns-name`）にアクセスしてチャットを送信

---

## 📋 詳細なトラブルシューティング

詳しい説明が必要な場合は、以下を参照：
- [EC2_500_ERROR_FIX.md](./EC2_500_ERROR_FIX.md) - 完全なトラブルシューティングガイド

---

## 🔍 よくある質問

**Q: ログをどうやって確認するの？**
```bash
docker-compose logs backend --tail=50
docker-compose logs backend -f  # リアルタイム
```

**Q: Bedrockが初期化されているか確認したい**
```bash
curl http://localhost:8000/
# "bedrock_client": "initialized" となっていればOK
```

**Q: AWS CLIでBedrockにアクセスできるか確認したい**
```bash
aws bedrock-runtime invoke-model \
  --model-id anthropic.claude-3-sonnet-20240229-v1:0 \
  --body '{"anthropic_version":"bedrock-2023-05-31","max_tokens":50,"messages":[{"role":"user","content":"Hi"}]}' \
  --region ap-northeast-1 \
  output.json

cat output.json
```

**Q: 完全にやり直したい**
```bash
# すべてクリーンアップ
docker-compose down -v
docker system prune -a -f

# 再デプロイ
chmod +x deploy-ec2.sh
./deploy-ec2.sh
```

---

## 📞 サポート

問題が解決しない場合は、以下の情報を集めてください：

```bash
# 診断結果
./diagnose.sh > diagnosis.txt

# ログ
docker-compose logs backend --tail=100 > backend.log
docker-compose logs frontend --tail=100 > frontend.log

# 設定ファイル
cat .env > config.txt
cat docker-compose.yml >> config.txt
```

これらのファイルを確認して、問題の原因を特定できます。
