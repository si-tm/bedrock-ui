# ALB設定の診断と修正ガイド

## 現在の問題

ブラウザが以下のURLにアクセスしています：
```
http://alb-hyakuzuka-891406204.ap-northeast-1.elb.amazonaws.com:3000/api/chat
```

これは **404 Not Found** エラーになっています。

## 問題の原因

### 1. ポート番号が含まれている
- ブラウザが `:3000` でアクセス
- ALBはポート番号なしでアクセスする必要がある

### 2. ALBリスナーの設定が不完全
- ALBにHTTPリスナー（ポート80）が設定されていない可能性
- または、ポート3000でリスナーが設定されている（これは間違い）

## 正しい構成

```
Internet (Browser)
  │
  ├─ HTTP  (port 80)  → ALB Listener (80)
  └─ HTTPS (port 443) → ALB Listener (443)
                          │
                          ├─ Rule 1: /api/*  → Backend TG (port 8000)
                          └─ Rule 2: Default → Frontend TG (port 3000)
```

## 修正手順

### ステップ1: ALBリスナーの確認

```bash
# ALBのリスナーを確認
aws elbv2 describe-listeners \
  --load-balancer-arn arn:aws:elasticloadbalancing:ap-northeast-1:ACCOUNT_ID:loadbalancer/app/alb-hyakuzuka/xxx

# 期待される出力:
# - Port: 80, Protocol: HTTP
# - Port: 443, Protocol: HTTPS (オプション)
```

### ステップ2: 正しいアクセス方法

#### ❌ 間違ったアクセス方法
```
http://alb-hyakuzuka-891406204.ap-northeast-1.elb.amazonaws.com:3000
http://alb-hyakuzuka-891406204.ap-northeast-1.elb.amazonaws.com:8000
```

#### ✅ 正しいアクセス方法
```
http://alb-hyakuzuka-891406204.ap-northeast-1.elb.amazonaws.com
```

**理由**: ALBはポート80（HTTP）または443（HTTPS）でリクエストを受け取り、内部的にターゲットグループのポート（3000や8000）に転送します。

### ステップ3: ALBリスナーの作成（HTTPポート80）

AWSコンソールまたはCLIでHTTPリスナーを作成：

#### AWSコンソールの場合

1. **EC2 → Load Balancers** を開く
2. `alb-hyakuzuka` を選択
3. **Listeners** タブを選択
4. **Add listener** をクリック

**リスナー設定（HTTP - ポート80）:**
- Protocol: `HTTP`
- Port: `80`
- Default action: Forward to `bedrock-ui-frontend-tg`

5. **Add rule** で追加ルールを作成

**ルール1（優先度: 1）:**
- **IF**: Path is
  - `/api/*`
  - `/health`
  - `/docs`
- **THEN**: Forward to `bedrock-ui-backend-tg`

#### AWS CLIの場合

```bash
# 1. HTTPリスナーを作成（ポート80）
aws elbv2 create-listener \
  --load-balancer-arn arn:aws:elasticloadbalancing:ap-northeast-1:ACCOUNT_ID:loadbalancer/app/alb-hyakuzuka/xxx \
  --protocol HTTP \
  --port 80 \
  --default-actions Type=forward,TargetGroupArn=arn:aws:elasticloadbalancing:ap-northeast-1:ACCOUNT_ID:targetgroup/bedrock-ui-frontend-tg/xxx

# 2. APIルールを追加（優先度1）
aws elbv2 create-rule \
  --listener-arn arn:aws:elasticloadbalancing:ap-northeast-1:ACCOUNT_ID:listener/app/alb-hyakuzuka/xxx/xxx \
  --priority 1 \
  --conditions Field=path-pattern,Values='/api/*' Field=path-pattern,Values='/health' Field=path-pattern,Values='/docs' \
  --actions Type=forward,TargetGroupArn=arn:aws:elasticloadbalancing:ap-northeast-1:ACCOUNT_ID:targetgroup/bedrock-ui-backend-tg/xxx
```

### ステップ4: セキュリティグループの確認

#### ALBのセキュリティグループ

**インバウンドルール:**
```
Type        Protocol    Port    Source
HTTP        TCP         80      0.0.0.0/0
HTTPS       TCP         443     0.0.0.0/0 (オプション)
```

**アウトバウンドルール:**
```
Type        Protocol    Port    Destination
All traffic All         All     0.0.0.0/0
```

#### EC2/ECSのセキュリティグループ

**インバウンドルール:**
```
Type        Protocol    Port    Source
Custom TCP  TCP         8000    <ALB Security Group>
Custom TCP  TCP         3000    <ALB Security Group>
```

### ステップ5: ターゲットグループの登録確認

```bash
# フロントエンドターゲットグループ
aws elbv2 describe-target-health \
  --target-group-arn arn:aws:elasticloadbalancing:ap-northeast-1:ACCOUNT_ID:targetgroup/bedrock-ui-frontend-tg/xxx

# バックエンドターゲットグループ
aws elbv2 describe-target-health \
  --target-group-arn arn:aws:elasticloadbalancing:ap-northeast-1:ACCOUNT_ID:targetgroup/bedrock-ui-backend-tg/xxx

# 期待される状態: "State": "healthy"
```

### ステップ6: 動作確認

#### 1. ブラウザでアクセス（ポート番号なし）

```
http://alb-hyakuzuka-891406204.ap-northeast-1.elb.amazonaws.com
```

#### 2. curlでテスト

```bash
# フロントエンドにアクセス
curl http://alb-hyakuzuka-891406204.ap-northeast-1.elb.amazonaws.com

# バックエンドヘルスチェック
curl http://alb-hyakuzuka-891406204.ap-northeast-1.elb.amazonaws.com/health

# APIエンドポイント
curl -X POST http://alb-hyakuzuka-891406204.ap-northeast-1.elb.amazonaws.com/api/chat \
  -H "Content-Type: application/json" \
  -d '{"message":"test","conversation_history":[]}'
```

#### 3. 開発者ツールで確認

1. ブラウザで `http://alb-hyakuzuka-891406204.ap-northeast-1.elb.amazonaws.com` を開く
2. F12 → Network タブ
3. チャットでメッセージを送信
4. リクエストURLを確認

**✅ 期待される結果:**
```
Request URL: http://alb-hyakuzuka-891406204.ap-northeast-1.elb.amazonaws.com/api/chat
Status: 200 OK
```

## トラブルシューティング

### 問題: まだ `:3000` が付いている

**原因**: ブラウザが直接 `:3000` でアクセスしている

**解決策**: ALBのDNS名を**ポート番号なし**でアクセス
```
http://alb-hyakuzuka-891406204.ap-northeast-1.elb.amazonaws.com
```

### 問題: 404 エラーが続く

**原因1**: リスナールールが正しく設定されていない

**確認方法**:
```bash
# リスナールールを確認
aws elbv2 describe-rules \
  --listener-arn arn:aws:elasticloadbalancing:ap-northeast-1:ACCOUNT_ID:listener/app/alb-hyakuzuka/xxx/xxx
```

**原因2**: ターゲットグループが登録されていない

**確認方法**:
```bash
# ターゲットを確認
aws elbv2 describe-target-health \
  --target-group-arn arn:aws:elasticloadbalancing:ap-northeast-1:ACCOUNT_ID:targetgroup/bedrock-ui-backend-tg/xxx
```

### 問題: 502 Bad Gateway

**原因**: ターゲット（EC2/ECS）が unhealthy

**解決策**:
1. ヘルスチェックパスが `/health` であることを確認
2. セキュリティグループでポート8000と3000が開いていることを確認
3. コンテナが正常に起動していることを確認

## まとめ

### 重要なポイント

1. ✅ ALBには**ポート番号なし**でアクセス
   - `http://your-alb.com` （OK）
   - `http://your-alb.com:3000` （NG）

2. ✅ ALBリスナーはポート80（HTTP）で受付
   - 内部的にポート3000（Frontend）と8000（Backend）に転送

3. ✅ リスナールールの優先度
   - 優先度1: `/api/*` → Backend
   - デフォルト: その他 → Frontend

4. ✅ セキュリティグループ
   - ALB: ポート80を許可
   - EC2/ECS: ALBからのポート3000と8000を許可

### 構成図

```
Browser
  │
  │ http://your-alb.com (port 80)
  ▼
┌─────────────────────┐
│   ALB (port 80)     │
│                     │
│  Rule Priority:     │
│  1: /api/* → 8000   │
│  2: Default → 3000  │
└─────────────────────┘
  │              │
  │              │
  ▼              ▼
Frontend       Backend
(port 3000)    (port 8000)
```
