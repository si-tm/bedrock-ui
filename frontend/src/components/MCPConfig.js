import React, { useState, useEffect } from 'react';
import axios from 'axios';
import './MCPConfig.css';

// 本番環境（ALB）では相対パスを使用
const getApiUrl = () => {
  if (window.location.hostname === 'localhost' || window.location.hostname === '127.0.0.1') {
    return 'http://localhost:8000';
  }
  return '';
};

const API_URL = getApiUrl();

function MCPConfig() {
  const [configJson, setConfigJson] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const [message, setMessage] = useState('');

  useEffect(() => {
    fetchConfig();
  }, []);

  const fetchConfig = async () => {
    try {
      const response = await axios.get(`${API_URL}/api/mcp/config`);
      setConfigJson(JSON.stringify(response.data, null, 2));
    } catch (error) {
      console.error('Error fetching config:', error);
      setConfigJson('{\n  "servers": [],\n  "description": "MCP Server Configuration"\n}');
    }
  };

  const handleSave = async (e) => {
    e.preventDefault();
    
    setIsLoading(true);
    setMessage('');

    try {
      const config = JSON.parse(configJson);
      await axios.post(`${API_URL}/api/mcp/config`, config);
      setMessage('設定を保存しました');
      setTimeout(() => setMessage(''), 3000);
    } catch (error) {
      if (error instanceof SyntaxError) {
        setMessage('JSONの形式が正しくありません');
      } else {
        setMessage('設定の保存に失敗しました');
      }
      console.error('Error saving config:', error);
    } finally {
      setIsLoading(false);
    }
  };

  const handleFormat = () => {
    try {
      const config = JSON.parse(configJson);
      setConfigJson(JSON.stringify(config, null, 2));
      setMessage('フォーマットしました');
      setTimeout(() => setMessage(''), 2000);
    } catch (error) {
      setMessage('JSONの形式が正しくありません');
    }
  };

  return (
    <div className="mcp-container">
      <h2>MCP設定</h2>
      <p className="description">
        MCPサーバーの設定をJSON形式で管理します。
      </p>

      <div className="config-editor">
        <div className="editor-header">
          <h3>設定JSON</h3>
          <button
            type="button"
            onClick={handleFormat}
            className="format-button"
          >
            フォーマット
          </button>
        </div>

        <form onSubmit={handleSave}>
          <textarea
            value={configJson}
            onChange={(e) => setConfigJson(e.target.value)}
            className="json-input"
            rows="20"
            spellCheck="false"
          />
          
          {message && (
            <div className={`message ${message.includes('失敗') || message.includes('正しくありません') ? 'error' : 'success'}`}>
              {message}
            </div>
          )}

          <button
            type="submit"
            className="save-button"
            disabled={isLoading}
          >
            {isLoading ? '保存中...' : '設定を保存'}
          </button>
        </form>
      </div>

      <div className="config-example">
        <h3>設定例</h3>
        <pre>{`{
  "servers": [
    {
      "name": "example-server",
      "command": "python",
      "args": ["-m", "mcp_server"],
      "env": {
        "API_KEY": "your-api-key"
      }
    }
  ],
  "description": "MCP Server Configuration"
}`}</pre>
      </div>
    </div>
  );
}

export default MCPConfig;
