import React, { useState } from 'react';
import { BrowserRouter as Router, Routes, Route, Link } from 'react-router-dom';
import Chat from './components/Chat';
import DiagramGenerator from './components/DiagramGenerator';
import MCPConfig from './components/MCPConfig';
import './App.css';

function App() {
  return (
    <Router>
      <div className="App">
        <nav className="navbar">
          <div className="nav-container">
            <h1 className="nav-title">Bedrock UI</h1>
            <ul className="nav-menu">
              <li className="nav-item">
                <Link to="/" className="nav-link">チャット</Link>
              </li>
              <li className="nav-item">
                <Link to="/diagram" className="nav-link">構成図生成</Link>
              </li>
              <li className="nav-item">
                <Link to="/mcp" className="nav-link">MCP設定</Link>
              </li>
            </ul>
          </div>
        </nav>
        
        <main className="main-content">
          <Routes>
            <Route path="/" element={<Chat />} />
            <Route path="/diagram" element={<DiagramGenerator />} />
            <Route path="/mcp" element={<MCPConfig />} />
          </Routes>
        </main>
      </div>
    </Router>
  );
}

export default App;
