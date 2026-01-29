from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import boto3
import json
import os

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
bedrock_runtime = boto3.client(
    service_name='bedrock-runtime',
    region_name=os.getenv('AWS_REGION', 'us-east-1')
)

class ChatRequest(BaseModel):
    message: str
    conversation_history: list = []

class DiagramRequest(BaseModel):
    description: str

@app.get("/")
async def root():
    return {"message": "Bedrock UI API is running"}

@app.get("/health")
async def health_check():
    """ヘルスチェックエンドポイント"""
    return {
        "status": "healthy",
        "service": "bedrock-ui-backend"
    }

@app.post("/api/chat")
async def chat(request: ChatRequest):
    """チャット機能のエンドポイント"""
    try:
        # Claude モデルを使用
        messages = request.conversation_history + [
            {"role": "user", "content": request.message}
        ]
        
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
        
        return {
            "response": assistant_message,
            "conversation_history": messages + [
                {"role": "assistant", "content": assistant_message}
            ]
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/diagram")
async def generate_diagram(request: DiagramRequest):
    """構成図生成機能のエンドポイント"""
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
        
        return {"diagram": diagram_code}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/mcp/config")
async def get_mcp_config():
    """MCP設定の取得"""
    # 実装例: 設定ファイルから読み込み
    return {
        "servers": [],
        "description": "MCP Server Configuration"
    }

@app.post("/api/mcp/config")
async def update_mcp_config(config: dict):
    """MCP設定の更新"""
    try:
        # 実装例: 設定ファイルへの書き込み
        return {"status": "success", "config": config}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
