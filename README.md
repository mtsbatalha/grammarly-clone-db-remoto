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
│   Redis    │    │    MySQL     │
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
- **Database**: MySQL 8.0+
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
- pnpm 9+
- Docker Desktop (para Redis)
- Ollama (opcional, para IA local)

> **Nota:** O banco de dados MySQL é remoto (Neon). Apenas o Redis roda localmente via Docker.

### 1. Clone e Instale

```bash
git clone https://github.com/seu-usuario/grammarly-clone.git
cd grammarly-clone
pnpm install
```

### 2. Configure o Ambiente

```bash
cp .env.example .env
# Edite .env com suas configurações (DATABASE_URL, etc.)
```

### 3. Setup Completo (do zero)

```powershell
# Windows
.\scripts\windows\setup.ps1

# Linux/Mac
./scripts/linux/setup.sh
```

O setup interativo vai:
- Detectar se o banco é local ou remoto
- Parar e remover containers antigos
- Reconstruir containers do zero
- Rodar migrações do Prisma
- Verificar se todos os serviços estão saudáveis

### 4. Instale o Ollama (opcional)

```bash
# Windows
winget install Ollama.Ollama

# Linux/Mac
curl -fsSL https://ollama.com/install.sh | sh

# Baixe o modelo recomendado
ollama pull mistral
```

---

## ▶️ Iniciando o Projeto

### Opção 1: Script completo (recomendado)

Inicia Docker (Redis), verifica portas, e roda API + Web:

```powershell
# Windows
.\scripts\windows\start.ps1

# Linux/Mac
./scripts/linux/start.sh
```

Opções do start:
```powershell
.\scripts\windows\start.ps1 -Auto          # Usa portas alternativas automaticamente
.\scripts\windows\start.ps1 -ApiPort 4000   # Define porta da API manualmente
```

### Opção 2: Via npm scripts

```bash
# Iniciar tudo (Docker + API + Web)
pnpm start:all

# Iniciar com cache limpo
pnpm start:clean

# Reconstruir containers e iniciar
pnpm start:rebuild

# Iniciar apenas a API
pnpm dev:api

# Iniciar apenas o Web
pnpm dev:web

# Iniciar API + Web (sem Docker)
pnpm dev
```

### Opção 3: Docker manualmente

```bash
# Subir Redis (DB remoto)
docker compose -f docker-compose.dev.yml up -d

# Subir e iniciar dev
pnpm dev
```

### URLs padrão

| Serviço | URL |
|---------|-----|
| Web (Frontend) | http://localhost:5173 |
| API (Backend) | http://localhost:3003 |
| Redis | localhost:6381 |

---

## ⏹️ Parando o Projeto

```powershell
# Windows - Para containers Docker
.\scripts\windows\stop.ps1

# Windows - Para e remove override de portas
.\scripts\windows\stop.ps1 -Clean

# Linux/Mac
./scripts/linux/stop.sh
```

Via npm:
```bash
pnpm stop
```

Para matar processos Node.js presos nas portas:
```powershell
# Windows
.\scripts\windows\kill-processes.ps1

# Linux/Mac
./scripts/linux/kill-processes.sh
```

---

## 🔄 Reiniciando o Projeto

```powershell
# Windows - Reinicia containers Docker
.\scripts\windows\restart-containers.ps1

# Windows - Reinicia e reseta portas para o padrão
.\scripts\windows\restart-containers.ps1 -ResetPorts

# Linux/Mac
./scripts/linux/restart-containers.sh
```

---

## 🔨 Reconstruindo do Zero

### Setup completo (limpa tudo e reconfigura)
```powershell
# Windows
.\scripts\windows\setup.ps1

# Linux/Mac
./scripts/linux/setup.sh
```

### Limpar cache Docker e reiniciar
```bash
# Remove containers, volumes e cache
pnpm docker:clean

# Depois inicie novamente
pnpm start:all
```

### Reconstruir containers sem cache
```bash
pnpm start:rebuild
```

### Desinstalar completamente
```powershell
# Windows (remove containers, volumes, node_modules, builds)
.\scripts\windows\uninstall.ps1

# Linux/Mac
./scripts/linux/uninstall.sh
```

> **Atenção:** O uninstall remove TUDO localmente. O banco remoto (Neon) não é afetado.

---

## 📊 Verificando Status

```powershell
# Windows
.\scripts\windows\status.ps1              # Status básico
.\scripts\windows\status.ps1 -Detailed    # Status com logs e uso de recursos
.\scripts\windows\status.ps1 -Json        # Saída em JSON

# Linux/Mac
./scripts/linux/status.sh
```

---

## 💾 Backup e Restore

```powershell
# Backup completo (banco + arquivos)
.\scripts\windows\backup.ps1

# Apenas banco de dados
.\scripts\windows\backup.ps1 -Database

# Apenas arquivos (.env, uploads, configs)
.\scripts\windows\backup.ps1 -Files

# Listar backups disponíveis
.\scripts\windows\backup.ps1 -List

# Restaurar um backup
.\scripts\windows\backup.ps1 -Restore "backup_full_20240101_120000.zip"
```

---

## 🗃️ Banco de Dados (Prisma)

```bash
# Sincronizar schema com o banco
pnpm db:migrate

# Popular banco com dados iniciais
pnpm db:seed

# Abrir Prisma Studio (interface visual)
pnpm db:studio
```

---

## 📜 Referência Completa de Scripts

### npm scripts (`package.json`)

| Comando | Descrição |
|---------|-----------|
| `pnpm dev` | Inicia API + Web em modo desenvolvimento |
| `pnpm dev:api` | Inicia apenas a API |
| `pnpm dev:web` | Inicia apenas o Web |
| `pnpm build` | Build de produção |
| `pnpm start` | Inicia em modo produção |
| `pnpm start:all` | Setup completo: Docker + dev |
| `pnpm start:clean` | Limpa Docker e reinicia tudo |
| `pnpm start:rebuild` | Reconstrói containers e reinicia |
| `pnpm stop` | Para containers Docker |
| `pnpm docker:clean` | Remove containers, volumes e cache |
| `pnpm docker:dev` | Sobe containers de desenvolvimento |
| `pnpm docker:dev:down` | Para containers de desenvolvimento |
| `pnpm db:migrate` | Roda migrações do Prisma |
| `pnpm db:seed` | Popula o banco com dados iniciais |
| `pnpm db:studio` | Abre Prisma Studio |
| `pnpm lint` | Roda linter |
| `pnpm test` | Roda testes |
| `pnpm clean` | Remove node_modules e cache do Turbo |

### Scripts de plataforma

| Script | Windows | Linux/Mac |
|--------|---------|-----------|
| Iniciar | `.\scripts\windows\start.ps1` | `./scripts/linux/start.sh` |
| Parar | `.\scripts\windows\stop.ps1` | `./scripts/linux/stop.sh` |
| Reiniciar | `.\scripts\windows\restart-containers.ps1` | `./scripts/linux/restart-containers.sh` |
| Status | `.\scripts\windows\status.ps1` | `./scripts/linux/status.sh` |
| Setup | `.\scripts\windows\setup.ps1` | `./scripts/linux/setup.sh` |
| Backup | `.\scripts\windows\backup.ps1` | `./scripts/linux/backup.sh` |
| Kill processos | `.\scripts\windows\kill-processes.ps1` | `./scripts/linux/kill-processes.sh` |
| Desinstalar | `.\scripts\windows\uninstall.ps1` | `./scripts/linux/uninstall.sh` |
| Fix DB auth | `.\scripts\windows\fix-db-auth.ps1` | `./scripts/linux/fix-db-auth.sh` |

---

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
