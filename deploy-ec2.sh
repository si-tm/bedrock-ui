#!/bin/bash

# EC2上でのデプロイスクリプト (IMDSv2対応)
# このスクリプトは、EC2インスタンスでdocker-composeを使用してアプリケーションをデプロイします

echo "=========================================="
echo "Bedrock UI - EC2デプロイスクリプト"
echo "=========================================="

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

# .envファイルが存在しない場合は作成
if [ ! -f .env ]; then
    echo "✓ .envファイルを作成中..."
    cat > .env << 'EOF'
# AWS設定 - EC2本番環境用
AWS_REGION=ap-northeast-1

# EC2ではIAMロールから自動取得されるため、以下は不要
# AWS_ACCESS_KEY_ID=
# AWS_SECRET_ACCESS_KEY=

# フロントエンド設定（ALB環境では不要）
# REACT_APP_API_URL=
EOF
else
    echo "✓ .envファイルが既に存在します"
fi

# AWS_REGIONの確認
echo ""
echo "✓ 環境変数の確認..."
source .env 2>/dev/null
echo "  AWS_REGION: ${AWS_REGION:-ap-northeast-1}"

# IAMロールの確認 (IMDSv2対応)
echo ""
echo "✓ IAMロールの確認..."
ROLE_NAME=$(get_metadata "iam/security-credentials/")

if [ -n "$ROLE_NAME" ]; then
    echo "  IAMロール: $ROLE_NAME ✓"
    
    # 認証情報の確認
    TOKEN=$(get_imds_token)
    if [ -z "$TOKEN" ]; then
        CREDS=$(curl -s "http://169.254.169.254/latest/meta-data/iam/security-credentials/$ROLE_NAME" 2>/dev/null)
    else
        CREDS=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
            "http://169.254.169.254/latest/meta-data/iam/security-credentials/$ROLE_NAME" 2>/dev/null)
    fi
    
    if echo "$CREDS" | grep -q "AccessKeyId"; then
        echo "  認証情報: 取得成功 ✓"
    else
        echo "  ⚠️  警告: 認証情報の取得に失敗しました"
    fi
else
    echo "  ⚠️  警告: IAMロールがアタッチされていません"
    echo "  IAMロールがないと、AWS Bedrockにアクセスできません"
    echo ""
    echo "  対処方法："
    echo "  1. EC2コンソールでインスタンスを選択"
    echo "  2. アクション > セキュリティ > IAMロールを変更"
    echo "  3. bedrock-ui-ec2-role を選択してアタッチ"
    echo ""
    read -p "続行しますか? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# 既存のコンテナを停止
echo ""
echo "✓ 既存のコンテナを停止中..."
docker-compose down

# イメージを再ビルド
echo ""
echo "✓ Dockerイメージをビルド中..."
docker-compose build --no-cache

# コンテナを起動
echo ""
echo "✓ コンテナを起動中..."
docker-compose up -d

# 起動確認
echo ""
echo "✓ コンテナの起動を確認中..."
sleep 10

# ヘルスチェック
echo ""
echo "=========================================="
echo "ヘルスチェック"
echo "=========================================="

echo ""
echo "1. バックエンドのヘルスチェック:"
if curl -s -f http://localhost:8000/health > /dev/null; then
    echo "   ✓ バックエンドは正常に起動しています"
    curl -s http://localhost:8000/ | python3 -m json.tool 2>/dev/null || curl -s http://localhost:8000/
else
    echo "   ✗ バックエンドが起動していません"
    echo ""
    echo "   ログを確認してください:"
    echo "   docker-compose logs backend"
fi

echo ""
echo "2. フロントエンドのヘルスチェック:"
if curl -s -f http://localhost:3000/health > /dev/null; then
    echo "   ✓ フロントエンドは正常に起動しています"
else
    echo "   ✗ フロントエンドが起動していません"
    echo ""
    echo "   ログを確認してください:"
    echo "   docker-compose logs frontend"
fi

# Bedrock接続テスト
echo ""
echo "3. Bedrock接続テスト:"
BEDROCK_STATUS=$(curl -s http://localhost:8000/ | grep -o '"bedrock_client":"[^"]*"' | cut -d'"' -f4)
if [ "$BEDROCK_STATUS" = "initialized" ]; then
    echo "   ✓ Bedrockクライアントは初期化されています"
else
    echo "   ✗ Bedrockクライアントの初期化に失敗しました"
    echo ""
    echo "   以下を確認してください:"
    echo "   1. IAMロールがアタッチされているか"
    echo "   2. IAMロールに bedrock:InvokeModel 権限があるか"
    echo "   3. AWS Bedrock の Model Access が有効化されているか"
    echo ""
    echo "   詳細なログを確認:"
    echo "   docker-compose logs backend | grep -E '(Bedrock|ERROR|✓|✗)'"
fi

echo ""
echo "=========================================="
echo "デプロイ完了"
echo "=========================================="
echo ""
echo "次のステップ:"
echo "1. 診断スクリプトを実行: ./diagnose.sh"
echo "2. ALB経由でアクセス: http://your-alb-dns-name"
echo "3. ログを確認: docker-compose logs -f backend"
echo "4. チャット機能をテスト"
echo ""
echo "トラブルシューティング:"
echo "- 詳細診断: ./diagnose.sh"
echo "- ログ確認: docker-compose logs backend"
echo "- コンテナ再起動: docker-compose restart backend"
echo "- 完全再デプロイ: ./deploy-ec2.sh"
echo ""
