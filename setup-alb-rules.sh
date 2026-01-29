# ALBリスナールール設定スクリプト

## ステップ1: リスナーARNを取得

```bash
# ALB名を設定
ALB_NAME="alb-hyakuzuka"
REGION="ap-northeast-1"

# ALB ARNを取得
ALB_ARN=$(aws elbv2 describe-load-balancers \
  --names $ALB_NAME \
  --region $REGION \
  --query 'LoadBalancers[0].LoadBalancerArn' \
  --output text)

echo "ALB ARN: $ALB_ARN"

# HTTP:80 リスナーARNを取得
LISTENER_ARN=$(aws elbv2 describe-listeners \
  --load-balancer-arn $ALB_ARN \
  --region $REGION \
  --query 'Listeners[?Port==`80`].ListenerArn' \
  --output text)

echo "HTTP:80 Listener ARN: $LISTENER_ARN"

# リスナーARNが取得できたか確認
if [ -z "$LISTENER_ARN" ]; then
  echo "エラー: HTTP:80 リスナーが見つかりません"
  exit 1
fi
```

## ステップ2: 既存のルールを確認

```bash
# 現在のルールを確認
aws elbv2 describe-rules \
  --listener-arn $LISTENER_ARN \
  --region $REGION
```

## ステップ3: APIルールを追加

```bash
# バックエンドターゲットグループARN
BACKEND_TG_ARN="arn:aws:elasticloadbalancing:ap-northeast-1:573576813930:targetgroup/bedrock-backend/32d880cc7ceb1fc7"

# ルールを作成（優先度1）
aws elbv2 create-rule \
  --listener-arn $LISTENER_ARN \
  --priority 1 \
  --conditions Field=path-pattern,Values='/api/*' \
  --actions Type=forward,TargetGroupArn=$BACKEND_TG_ARN \
  --region $REGION

echo "ルール1 (priority 1) を作成しました: /api/* -> bedrock-backend"
```

## ステップ4: ヘルスチェックルールを追加（オプション）

```bash
# ヘルスチェックルールを作成（優先度2）
aws elbv2 create-rule \
  --listener-arn $LISTENER_ARN \
  --priority 2 \
  --conditions Field=path-pattern,Values='/health' \
  --actions Type=forward,TargetGroupArn=$BACKEND_TG_ARN \
  --region $REGION

echo "ルール2 (priority 2) を作成しました: /health -> bedrock-backend"
```

## ステップ5: 不要なリスナーを削除

```bash
# HTTP:3000 リスナーARNを取得して削除
LISTENER_3000=$(aws elbv2 describe-listeners \
  --load-balancer-arn $ALB_ARN \
  --region $REGION \
  --query 'Listeners[?Port==`3000`].ListenerArn' \
  --output text)

if [ ! -z "$LISTENER_3000" ]; then
  aws elbv2 delete-listener \
    --listener-arn $LISTENER_3000 \
    --region $REGION
  echo "HTTP:3000 リスナーを削除しました"
fi

# HTTP:8000 リスナーARNを取得して削除
LISTENER_8000=$(aws elbv2 describe-listeners \
  --load-balancer-arn $ALB_ARN \
  --region $REGION \
  --query 'Listeners[?Port==`8000`].ListenerArn' \
  --output text)

if [ ! -z "$LISTENER_8000" ]; then
  aws elbv2 delete-listener \
    --listener-arn $LISTENER_8000 \
    --region $REGION
  echo "HTTP:8000 リスナーを削除しました"
fi
```

## ステップ6: 設定を確認

```bash
# 最終的なリスナー構成を確認
echo "=== リスナー一覧 ==="
aws elbv2 describe-listeners \
  --load-balancer-arn $ALB_ARN \
  --region $REGION \
  --query 'Listeners[*].[Port,Protocol]' \
  --output table

# HTTP:80のルールを確認
echo "=== HTTP:80 のルール一覧 ==="
aws elbv2 describe-rules \
  --listener-arn $LISTENER_ARN \
  --region $REGION \
  --query 'Rules[*].[Priority,Conditions[0].Values[0],Actions[0].TargetGroupArn]' \
  --output table
```

## ステップ7: 動作確認

```bash
ALB_DNS="alb-hyakuzuka-891406204.ap-northeast-1.elb.amazonaws.com"

# フロントエンドにアクセス
echo "=== フロントエンドテスト ==="
curl -I http://$ALB_DNS

# バックエンドヘルスチェック
echo "=== バックエンドヘルスチェック ==="
curl http://$ALB_DNS/health

# APIエンドポイント
echo "=== APIエンドポイントテスト ==="
curl -X POST http://$ALB_DNS/api/chat \
  -H "Content-Type: application/json" \
  -d '{"message":"test","conversation_history":[]}'
```

---

## 全コマンドを一度に実行

すべてのステップを一度に実行するスクリプト：

```bash
#!/bin/bash

# 設定
ALB_NAME="alb-hyakuzuka"
REGION="ap-northeast-1"
BACKEND_TG_ARN="arn:aws:elasticloadbalancing:ap-northeast-1:573576813930:targetgroup/bedrock-backend/32d880cc7ceb1fc7"

echo "=== ステップ1: リスナーARN取得 ==="
ALB_ARN=$(aws elbv2 describe-load-balancers --names $ALB_NAME --region $REGION --query 'LoadBalancers[0].LoadBalancerArn' --output text)
echo "ALB ARN: $ALB_ARN"

LISTENER_ARN=$(aws elbv2 describe-listeners --load-balancer-arn $ALB_ARN --region $REGION --query 'Listeners[?Port==`80`].ListenerArn' --output text)
echo "HTTP:80 Listener ARN: $LISTENER_ARN"

if [ -z "$LISTENER_ARN" ]; then
  echo "エラー: HTTP:80 リスナーが見つかりません"
  exit 1
fi

echo ""
echo "=== ステップ2: ルール作成 ==="
# /api/* ルール
aws elbv2 create-rule \
  --listener-arn $LISTENER_ARN \
  --priority 1 \
  --conditions Field=path-pattern,Values='/api/*' \
  --actions Type=forward,TargetGroupArn=$BACKEND_TG_ARN \
  --region $REGION 2>/dev/null && echo "✓ /api/* ルールを作成" || echo "! /api/* ルールは既に存在する可能性があります"

# /health ルール
aws elbv2 create-rule \
  --listener-arn $LISTENER_ARN \
  --priority 2 \
  --conditions Field=path-pattern,Values='/health' \
  --actions Type=forward,TargetGroupArn=$BACKEND_TG_ARN \
  --region $REGION 2>/dev/null && echo "✓ /health ルールを作成" || echo "! /health ルールは既に存在する可能性があります"

echo ""
echo "=== ステップ3: 不要なリスナー削除 ==="
LISTENER_3000=$(aws elbv2 describe-listeners --load-balancer-arn $ALB_ARN --region $REGION --query 'Listeners[?Port==`3000`].ListenerArn' --output text)
if [ ! -z "$LISTENER_3000" ]; then
  aws elbv2 delete-listener --listener-arn $LISTENER_3000 --region $REGION
  echo "✓ HTTP:3000 リスナーを削除"
fi

LISTENER_8000=$(aws elbv2 describe-listeners --load-balancer-arn $ALB_ARN --region $REGION --query 'Listeners[?Port==`8000`].ListenerArn' --output text)
if [ ! -z "$LISTENER_8000" ]; then
  aws elbv2 delete-listener --listener-arn $LISTENER_8000 --region $REGION
  echo "✓ HTTP:8000 リスナーを削除"
fi

echo ""
echo "=== ステップ4: 設定確認 ==="
echo "リスナー一覧:"
aws elbv2 describe-listeners --load-balancer-arn $ALB_ARN --region $REGION --query 'Listeners[*].[Port,Protocol]' --output table

echo ""
echo "HTTP:80 のルール一覧:"
aws elbv2 describe-rules --listener-arn $LISTENER_ARN --region $REGION --query 'Rules[*].[Priority,Conditions[0].Values[0],Actions[0].TargetGroupArn]' --output table

echo ""
echo "=== 完了 ==="
echo "ブラウザでアクセス: http://alb-hyakuzuka-891406204.ap-northeast-1.elb.amazonaws.com"
```

## 実行方法

```bash
# スクリプトをファイルに保存
cat > setup-alb.sh << 'EOF'
[上記のスクリプトをここに貼り付け]
EOF

# 実行権限を付与
chmod +x setup-alb.sh

# 実行
./setup-alb.sh
```
