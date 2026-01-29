from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import boto3
import json
import os
import logging

# ロギング設定
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="Bedrock UI API")

# CORS設定
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Bedrock クライアントの初期化
try:
    aws_region = os.getenv('AWS_REGION', 'us-east-1')
    logger.info(f"Initializing Bedrock client in region: {aws_region}")
    
    bedrock_runtime = boto3.client(
        service_name='bedrock-runtime',
        region_name=aws_region
    )
    logger.info("✓ Bedrock client initialized successfully")
except Exception as e:
    logger.error(f"✗ Failed to initialize Bedrock client: {e}")
    bedrock_runtime = None

class ChatRequest(BaseModel):
    message: str
    conversation_history: list = []

class DiagramRequest(BaseModel):
    description: str

@app.get("/")
async def root():
    return {
        "message": "Bedrock UI API is running",
        "region": os.getenv('AWS_REGION', 'us-east-1'),
        "bedrock_client": "initialized" if bedrock_runtime else "not initialized"
    }

@app.get("/health")
async def health_check():
    """ヘルスチェックエンドポイント"""
    return {
        "status": "healthy",
        "service": "bedrock-ui-backend",
        "region": os.getenv('AWS_REGION', 'us-east-1')
    }

@app.post("/api/chat")
async def chat(request: ChatRequest):
    """チャット機能のエンドポイント"""
    logger.info(f"Received chat request: {request.message[:50]}...")
    
    if not bedrock_runtime:
        logger.error("Bedrock client not initialized")
        raise HTTPException(
            status_code=500, 
            detail="Bedrock client not initialized. Please check AWS credentials and region."
        )
    
    try:
        # Claude モデルを使用
        messages = request.conversation_history + [
            {"role": "user", "content": request.message}
        ]
        
        logger.info(f"Calling Bedrock with {len(messages)} messages")
        
        body = json.dumps({
            "anthropic_version": "bedrock-2023-05-31",
            "max_tokens": 2000,
            "messages": messages,
            "temperature": 0.7
        })
        
        response = bedrock_runtime.invoke_model(
            modelId='anthropic.claude-3-sonnet-20240229-v1:0',
            body=body
        )
        
        response_body = json.loads(response['body'].read())
        assistant_message = response_body['content'][0]['text']
        
        logger.info(f"Bedrock response received: {len(assistant_message)} characters")
        
        return {
            "response": assistant_message,
            "conversation_history": messages + [
                {"role": "assistant", "content": assistant_message}
            ]
        }
    except Exception as e:
        logger.error(f"Error in chat endpoint: {type(e).__name__}: {str(e)}")
        
        # 詳細なエラーメッセージ
        error_detail = {
            "error_type": type(e).__name__,
            "error_message": str(e),
            "region": os.getenv('AWS_REGION', 'us-east-1')
        }
        
        # よくあるエラーの場合は説明を追加
        if "AccessDeniedException" in str(e):
            error_detail["hint"] = "IAMロールにbedrock:InvokeModel権限がありません"
        elif "ResourceNotFoundException" in str(e):
            error_detail["hint"] = "モデルが見つかりません。Bedrock Model Accessを確認してください"
        elif "ValidationException" in str(e):
            error_detail["hint"] = "リクエストの形式が正しくありません"
        elif "ThrottlingException" in str(e):
            error_detail["hint"] = "リクエスト制限に達しました。しばらく待ってから再試行してください"
        
        raise HTTPException(status_code=500, detail=error_detail)

@app.post("/api/diagram")
async def generate_diagram(request: DiagramRequest):
    """構成図生成機能のエンドポイント"""
    logger.info(f"Received diagram request: {request.description[:50]}...")
    
    if not bedrock_runtime:
        logger.error("Bedrock client not initialized")
        raise HTTPException(
            status_code=500, 
            detail="Bedrock client not initialized. Please check AWS credentials and region."
        )
    
    try:
        prompt = f"""
以下の説明に基づいて、AWS構成図をMermaid記法で生成してください。
適切なAWSサービスを選択し、それらの関係を示してください。

説明: {request.description}

Mermaid記法のみを返してください（コードブロックなし）。
"""
        
        body = json.dumps({
            "anthropic_version": "bedrock-2023-05-31",
            "max_tokens": 2000,
            "messages": [{"role": "user", "content": prompt}],
            "temperature": 0.5
        })
        
        response = bedrock_runtime.invoke_model(
            modelId='anthropic.claude-3-sonnet-20240229-v1:0',
            body=body
        )
        
        response_body = json.loads(response['body'].read())
        diagram_code = response_body['content'][0]['text']
        
        logger.info(f"Diagram generated: {len(diagram_code)} characters")
        
        return {"diagram": diagram_code}
    except Exception as e:
        logger.error(f"Error in diagram endpoint: {type(e).__name__}: {str(e)}")
        
        error_detail = {
            "error_type": type(e).__name__,
            "error_message": str(e),
            "region": os.getenv('AWS_REGION', 'us-east-1')
        }
        
        raise HTTPException(status_code=500, detail=error_detail)

@app.get("/api/mcp/config")
async def get_mcp_config():
    """MCP設定の取得"""
    return {
        "servers": [],
        "description": "MCP Server Configuration"
    }

@app.post("/api/mcp/config")
async def update_mcp_config(config: dict):
    """MCP設定の更新"""
    try:
        return {"status": "success", "config": config}
    except Exception as e:
        logger.error(f"Error updating MCP config: {e}")
        raise HTTPException(status_code=500, detail=str(e))
