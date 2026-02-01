#!/bin/bash

# このスクリプトは、EC2上で実行する前にスクリプトファイルに実行権限を付与します

echo "スクリプトファイルに実行権限を付与中..."

chmod +x deploy-ec2.sh
chmod +x diagnose.sh

echo "✓ 実行権限を付与しました"
echo ""
echo "次のステップ:"
echo "1. 診断を実行: ./diagnose.sh"
echo "2. デプロイを実行: ./deploy-ec2.sh"
