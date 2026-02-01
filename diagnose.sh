#!/bin/bash

# Bedrock UI 診断スクリプト
# EC2上でこのスクリプトを実行して、問題を診断します

echo "=========================================="
echo "Bedrock UI 診断スクリプト"
echo "=========================================="
echo ""

# カラーコード
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 1. AWS_REGION確認
echo "1. AWS_REGION設定の確認:"
if [ -f .env ]; then
    source .env 2>/dev/null
    if [ "$AWS_REGION" = "ap-northeast-1" ]; then
        echo -e "   ${GREEN}✓${NC} AWS_REGION: $AWS_REGION"
    else
        echo -e "   ${RED}✗${NC} AWS_REGION: ${AWS_REGION:-未設定} (ap-northeast-1 である必要があります)"
    fi
else
    echo -e "   ${YELLOW}⚠${NC} .envファイルが存在しません"
fi

# docker-compose.ymlのデフォルト値も確認
DEFAULT_REGION=$(grep "AWS_REGION=" docker-compose.yml | head -1 | grep -o ":-[^}]*" | cut -d'-' -f2 | cut -d'}' -f1)
if [ "$DEFAULT_REGION" = "ap-northeast-1" ]; then
    echo -e "   ${GREEN}✓${NC} docker-compose.yml のデフォルト: $DEFAULT_REGION"
else
    echo -e "   ${RED}✗${NC} docker-compose.yml のデフォルト: ${DEFAULT_REGION:-未設定} (ap-northeast-1 である必要があります)"
fi

# 2. IAMロール確認
echo ""
echo "2. IAMロールの確認:"
ROLE=$(curl -s --connect-timeout 2 http://169.254.169.254/latest/meta-data/iam/security-credentials/)
if [ -z "$ROLE" ]; then
    echo -e "   ${RED}✗${NC} IAMロールがアタッチされていません"
    echo "      EC2コンソールでIAMロールをアタッチしてください"
else
    echo -e "   ${GREEN}✓${NC} IAMロール: $ROLE"
    
    # ロールの認証情報を確認
    CREDS=$(curl -s http://169.254.169.254/latest/meta-data/iam/security-credentials/$ROLE)
    if echo "$CREDS" | grep -q "AccessKeyId"; then
        echo -e "   ${GREEN}✓${NC} 認証情報を取得できました"
    else
        echo -e "   ${RED}✗${NC} 認証情報の取得に失敗しました"
    fi
fi

# 3. Dockerコンテナの状態確認
echo ""
echo "3. Dockerコンテナの状態:"
if docker-compose ps 2>/dev/null | grep -q "backend"; then
    BACKEND_STATUS=$(docker-compose ps | grep backend | awk '{print $4}')
    if echo "$BACKEND_STATUS" | grep -q "Up"; then
        echo -e "   ${GREEN}✓${NC} バックエンドコンテナ: 起動中"
    else
        echo -e "   ${RED}✗${NC} バックエンドコンテナ: $BACKEND_STATUS"
    fi
else
    echo -e "   ${RED}✗${NC} バックエンドコンテナが見つかりません"
    echo "      docker-compose up -d を実行してください"
fi

# 4. バックエンドヘルスチェック
echo ""
echo "4. バックエンドのヘルスチェック:"
HEALTH_RESPONSE=$(curl -s -f http://localhost:8000/health 2>/dev/null)
if [ $? -eq 0 ]; then
    echo -e "   ${GREEN}✓${NC} バックエンドは正常に応答しています"
    echo "      $HEALTH_RESPONSE"
else
    echo -e "   ${RED}✗${NC} バックエンドが応答しません"
    echo "      docker-compose logs backend で確認してください"
fi

# 5. Bedrockクライアント初期化確認
echo ""
echo "5. Bedrockクライアントの初期化:"
ROOT_RESPONSE=$(curl -s http://localhost:8000/ 2>/dev/null)
BEDROCK_STATUS=$(echo "$ROOT_RESPONSE" | grep -o '"bedrock_client":"[^"]*"' | cut -d'"' -f4)
REGION=$(echo "$ROOT_RESPONSE" | grep -o '"region":"[^"]*"' | cut -d'"' -f4)

if [ "$BEDROCK_STATUS" = "initialized" ]; then
    echo -e "   ${GREEN}✓${NC} Bedrockクライアント: 初期化済み"
    echo -e "   ${GREEN}✓${NC} 使用リージョン: $REGION"
else
    echo -e "   ${RED}✗${NC} Bedrockクライアント: 初期化失敗"
    echo -e "   ${YELLOW}⚠${NC} 使用リージョン: $REGION"
fi

# 6. 最新のエラーログ確認
echo ""
echo "6. 最新のエラーログ:"
ERRORS=$(docker-compose logs backend --tail=20 2>/dev/null | grep -E "(ERROR|Exception|✗)" | tail -5)
if [ -z "$ERRORS" ]; then
    echo -e "   ${GREEN}✓${NC} エラーログはありません"
else
    echo -e "   ${RED}✗${NC} エラーが見つかりました:"
    echo "$ERRORS" | while IFS= read -r line; do
        echo "      $line"
    done
fi

# 7. Bedrock初期化ログ確認
echo ""
echo "7. Bedrock初期化ログ:"
INIT_LOGS=$(docker-compose logs backend 2>/dev/null | grep -E "(Bedrock|bedrock)" | tail -3)
if echo "$INIT_LOGS" | grep -q "✓"; then
    echo -e "   ${GREEN}✓${NC} 初期化成功"
    echo "$INIT_LOGS" | while IFS= read -r line; do
        echo "      $line"
    done
else
    echo -e "   ${RED}✗${NC} 初期化に問題がある可能性があります"
    echo "$INIT_LOGS" | while IFS= read -r line; do
        echo "      $line"
    done
fi

# 8. AWS CLI でBedrockアクセステスト
echo ""
echo "8. AWS CLI経由でBedrockアクセステスト:"
if command -v aws &> /dev/null; then
    TEST_RESULT=$(aws bedrock-runtime invoke-model \
        --model-id anthropic.claude-3-sonnet-20240229-v1:0 \
        --body '{"anthropic_version":"bedrock-2023-05-31","max_tokens":50,"messages":[{"role":"user","content":"Hi"}]}' \
        --region ap-northeast-1 \
        /tmp/bedrock-test.json 2>&1)
    
    if [ $? -eq 0 ]; then
        echo -e "   ${GREEN}✓${NC} Bedrockへの直接アクセス成功"
        echo "      AWS認証とBedrock設定は正常です"
    else
        echo -e "   ${RED}✗${NC} Bedrockへの直接アクセス失敗"
        if echo "$TEST_RESULT" | grep -q "AccessDeniedException"; then
            echo "      原因: IAMロールに bedrock:InvokeModel 権限がありません"
        elif echo "$TEST_RESULT" | grep -q "ResourceNotFoundException"; then
            echo "      原因: Bedrock Model Access が有効化されていません"
        elif echo "$TEST_RESULT" | grep -q "ValidationException"; then
            echo "      原因: モデルIDまたはリージョンに問題があります"
        else
            echo "      エラー: $TEST_RESULT"
        fi
    fi
    rm -f /tmp/bedrock-test.json
else
    echo -e "   ${YELLOW}⚠${NC} AWS CLIがインストールされていません"
fi

# 診断結果のサマリー
echo ""
echo "=========================================="
echo "診断結果サマリー"
echo "=========================================="

# 問題がある項目をカウント
ISSUES=0

[ "$AWS_REGION" != "ap-northeast-1" ] && ((ISSUES++)) && echo -e "${RED}✗${NC} AWS_REGIONをap-northeast-1に設定してください"
[ -z "$ROLE" ] && ((ISSUES++)) && echo -e "${RED}✗${NC} EC2にIAMロールをアタッチしてください"
[ "$BEDROCK_STATUS" != "initialized" ] && ((ISSUES++)) && echo -e "${RED}✗${NC} Bedrockクライアントの初期化に失敗しています"
[ ! -z "$ERRORS" ] && ((ISSUES++)) && echo -e "${RED}✗${NC} エラーログを確認してください: docker-compose logs backend"

if [ $ISSUES -eq 0 ]; then
    echo -e "${GREEN}✓${NC} すべての診断項目をパスしました！"
    echo ""
    echo "ALB経由でアクセスしてチャット機能をテストしてください"
else
    echo -e "${RED}✗${NC} $ISSUES 個の問題が見つかりました"
    echo ""
    echo "推奨される対処法:"
    echo "1. EC2_500_ERROR_FIX.md を参照"
    echo "2. 問題を修正後、以下を実行:"
    echo "   docker-compose down"
    echo "   docker-compose up -d"
    echo "3. このスクリプトを再実行して確認"
fi

echo ""
echo "詳細なログを確認:"
echo "  docker-compose logs backend --tail=50"
echo "  docker-compose logs frontend --tail=50"
echo ""
