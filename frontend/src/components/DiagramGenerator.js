import React, { useState, useEffect, useRef } from 'react';
import axios from 'axios';
import mermaid from 'mermaid';
import './DiagramGenerator.css';

// ALB経由でアクセスする場合は相対パスを使用
const API_URL = process.env.REACT_APP_API_URL || '';

mermaid.initialize({ startOnLoad: true, theme: 'default' });

function DiagramGenerator() {
  const [description, setDescription] = useState('');
  const [diagram, setDiagram] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const diagramRef = useRef(null);

  useEffect(() => {
    if (diagram && diagramRef.current) {
      diagramRef.current.innerHTML = '';
      mermaid.render('diagram-preview', diagram).then(({ svg }) => {
        diagramRef.current.innerHTML = svg;
      }).catch(error => {
        console.error('Mermaid rendering error:', error);
        diagramRef.current.innerHTML = '<p style="color: red;">図の表示に失敗しました</p>';
      });
    }
  }, [diagram]);

  const handleGenerate = async (e) => {
    e.preventDefault();
    
    if (!description.trim() || isLoading) return;

    setIsLoading(true);
    setDiagram('');

    try {
      const response = await axios.post(`${API_URL}/api/diagram`, {
        description
      });

      setDiagram(response.data.diagram);
    } catch (error) {
      console.error('Error generating diagram:', error);
      alert('構成図の生成に失敗しました。もう一度お試しください。');
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <div className="diagram-container">
      <h2>AWS構成図生成</h2>
      
      <form onSubmit={handleGenerate} className="diagram-form">
        <textarea
          value={description}
          onChange={(e) => setDescription(e.target.value)}
          placeholder="構成の説明を入力してください（例：EC2インスタンスがRDSデータベースに接続し、ALB経由でアクセスされる3層構成）"
          className="description-input"
          rows="5"
          disabled={isLoading}
        />
        <button
          type="submit"
          className="generate-button"
          disabled={isLoading || !description.trim()}
        >
          {isLoading ? '生成中...' : '構成図を生成'}
        </button>
      </form>

      {diagram && (
        <div className="diagram-preview">
          <h3>生成された構成図</h3>
          <div ref={diagramRef} className="mermaid-container"></div>
          
          <div className="diagram-code">
            <h4>Mermaidコード</h4>
            <pre>{diagram}</pre>
          </div>
        </div>
      )}
    </div>
  );
}

export default DiagramGenerator;
