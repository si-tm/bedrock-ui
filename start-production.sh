# 本番環境（EC2/ECS）用の起動スクリプト

#!/bin/bash

# 環境変数をクリア（ALB環境では相対パスを使用）
unset REACT_APP_API_URL

# .envファイルが存在する場合、REACT_APP_API_URLをコメントアウト
if [ -f .env ]; then
  sed -i.bak 's/^REACT_APP_API_URL=/#REACT_APP_API_URL=/' .env
fi

# 本番環境用Docker Composeで起動
docker-compose -f docker-compose.prod.yml down
docker-compose -f docker-compose.prod.yml build --no-cache
docker-compose -f docker-compose.prod.yml up -d

echo "✅ アプリケーションが起動しました"
echo ""
echo "ヘルスチェック:"
echo "  Backend:  curl http://localhost:8000/health"
echo "  Frontend: curl http://localhost:3000/health"
echo ""
echo "ログ確認:"
echo "  docker-compose -f docker-compose.prod.yml logs -f"
