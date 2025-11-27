# GrammarlyClone - Sistema de Correção Gramatical Inteligente

![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)

## 📋 Visão Geral

Clone completo do Grammarly com suporte para Português e Inglês, incluindo:
- **Extensão de Navegador** (Chrome/Firefox)
- **Dashboard Web** com editor interno
- **API REST** documentada
- **IA Local** 100% gratuita (Ollama/GPT4All)

## 🏗️ Arquitetura

```
┌─────────────────────────────────────────────────────────────────┐
│                        CLIENTE                                   │
├─────────────────────┬───────────────────────────────────────────┤
│  Browser Extension  │           Web Dashboard                    │
│  (Chrome/Firefox)   │         (React + TypeScript)              │
└─────────┬───────────┴───────────────────┬───────────────────────┘
          │                               │
          │         WebSocket + REST      │
          └───────────────┬───────────────┘
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│                      API GATEWAY                                 │
│                   (Node.js + Express)                           │
├─────────────────────────────────────────────────────────────────┤
│  Auth  │  Grammar  │  Style  │  Tone  │  History  │  Users     │
└────────┴─────┬─────┴─────────┴────────┴───────────┴─────────────┘
               │
    ┌──────────┴──────────┐
    ▼                     ▼
┌────────────┐    ┌──────────────┐
│   Redis    │    │  PostgreSQL  │
│  (Cache)   │    │   (Data)     │
└────────────┘    └──────────────┘
               │
               ▼
┌─────────────────────────────────────────────────────────────────┐
│                    AI ABSTRACTION LAYER                          │
├─────────────────────────────────────────────────────────────────┤
│  Ollama (Mistral/Llama)  │  GPT4All  │  DeepSeek  │  Custom    │
└─────────────────────────────────────────────────────────────────┘
```

## 🚀 Tecnologias

### Backend
- **Runtime**: Node.js 20+ com TypeScript
- **Framework**: Express.js + Socket.io
- **ORM**: Prisma
- **Database**: PostgreSQL 15+
- **Cache**: Redis 7+
- **Validação**: Zod
- **Auth**: JWT + bcrypt

### Frontend (Dashboard)
- **Framework**: React 18 + TypeScript
- **Build**: Vite
- **State**: Zustand
- **Styling**: Tailwind CSS
- **Editor**: TipTap (ProseMirror)

### Extensão
- **Manifest**: V3 (Chrome/Firefox compatível)
- **Build**: Webpack
- **UI**: Vanilla JS + Shadow DOM

### IA (100% Gratuita)
- **Recomendado**: Ollama com Mistral 7B
- **Alternativas**: GPT4All, DeepSeek, Llama 3

## 📁 Estrutura do Projeto

```
grammarly-clone/
├── apps/
│   ├── api/                 # Backend Node.js
│   ├── web/                 # Dashboard React
│   └── extension/           # Browser Extension
├── packages/
│   ├── shared/              # Tipos e utils compartilhados
│   ├── ai-provider/         # Camada de abstração de IA
│   └── grammar-engine/      # Motor de correção
├── docker/                  # Docker configs
├── docs/                    # Documentação
└── scripts/                 # Scripts de automação
```

## 🔧 Instalação Rápida

### Pré-requisitos
- Node.js 20+
- PostgreSQL 15+
- Redis 7+
- Ollama (para IA local)

### 1. Clone e Instale

```bash
git clone https://github.com/seu-usuario/grammarly-clone.git
cd grammarly-clone
npm install
```

### 2. Configure o Ambiente

```bash
cp .env.example .env
# Edite .env com suas configurações
```

### 3. Inicie os Serviços

```bash
# Com Docker (recomendado)
docker-compose up -d

# Ou manualmente
npm run dev
```

### 4. Instale o Ollama

```bash
# Windows
winget install Ollama.Ollama

# Linux/Mac
curl -fsSL https://ollama.com/install.sh | sh

# Baixe o modelo recomendado
ollama pull mistral
```

## 📖 Documentação

- [Guia de Instalação Completo](docs/INSTALLATION.md)
- [Documentação da API](docs/API.md)
- [Guia da Extensão](docs/EXTENSION.md)
- [Arquitetura Detalhada](docs/ARCHITECTURE.md)

## 🎯 Funcionalidades

### Correção Gramatical
- ✅ Erros ortográficos
- ✅ Concordância verbal/nominal
- ✅ Pontuação
- ✅ Regência verbal

### Sugestões de Estilo
- ✅ Clareza
- ✅ Concisão
- ✅ Formalidade
- ✅ Vocabulário

### Ajustes de Tom
- ✅ Formal/Informal
- ✅ Confiante/Neutro
- ✅ Amigável/Profissional
- ✅ Direto/Diplomático

### Sistema de Usuários
- ✅ Registro/Login
- ✅ Planos Free/Pro
- ✅ Preferências
- ✅ Histórico

## 📜 Licença

MIT License - veja [LICENSE](LICENSE) para detalhes.
