#!/bin/bash

# ===========================================
# Sincroniza a senha do banco de dados e reinicia a API
# ===========================================

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Obter raiz do projeto
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT" || exit 1

echo -e "${CYAN}--- Sincronizando Autenticação do Banco de Dados ---${NC}"

# 1. Obter a senha correta do POSTGRES_PASSWORD no docker-compose.yml
CORRECT_PASSWORD=$(grep "POSTGRES_PASSWORD:" docker-compose.yml | awk '{print $2}' | tr -d '\r')

if [ -n "$CORRECT_PASSWORD" ]; then
    echo -e "${GREEN}[✓] Senha configurada encontrada: $CORRECT_PASSWORD${NC}"
else
    echo -e "${RED}[✗] Erro: Não foi possível encontrar POSTGRES_PASSWORD no docker-compose.yml${NC}"
    exit 1
fi

# 2. Corrigir o DATABASE_URL se estiver errado no arquivo
# Busca a senha atual na URL (entre : e @)
CURRENT_PASSWORD_URL=$(grep "DATABASE_URL=" docker-compose.yml | sed -n 's/.*postgres:\(.*\)@.*postgres.*/\1/p' | tr -d '\r')

if [ "$CURRENT_PASSWORD_URL" != "$CORRECT_PASSWORD" ]; then
    echo -e "${YELLOW}[!] Senha na DATABASE_URL está divergente ($CURRENT_PASSWORD_URL). Corrigindo...${NC}"
    # Escapa caracteres especiais na senha para o sed
    ESCAPED_CURRENT=$(echo "$CURRENT_PASSWORD_URL" | sed 's/[^^]/[&]/g; s/\^/\\^/g')
    sed -i "s/$ESCAPED_CURRENT/$CORRECT_PASSWORD/g" docker-compose.yml
    echo -e "${GREEN}[✓] docker-compose.yml atualizado.${NC}"
else
    echo -e "${GREEN}[✓] Senha na DATABASE_URL já está correta.${NC}"
fi

# 3. Remover arquivos .env residuais que causam conflitos
if [ -f "apps/api/.env" ]; then
    echo -e "${YELLOW}[!] Arquivo apps/api/.env detectado. Removendo para evitar conflitos...${NC}"
    rm apps/api/.env
    echo -e "${GREEN}[✓] Arquivo removido.${NC}"
fi

# 4. Reiniciar o container da API
echo -e "${CYAN}[*] Reiniciando container grammarly_api...${NC}"
docker compose up -d --build api

# 5. Forçar atualização da senha dentro do Postgres
echo -e "${CYAN}[*] Garantindo que a senha está aplicada no banco de dados...${NC}"
if docker exec grammarly_postgres psql -U postgres -d postgres -c "ALTER USER postgres WITH PASSWORD '$CORRECT_PASSWORD';" > /dev/null 2>&1; then
    echo -e "${GREEN}[✓] Senha sincronizada internamente no Postgres.${NC}"
else
    echo -e "${YELLOW}[!] Aviso: Não foi possível rodar o comando SQL diretamente no container.${NC}"
fi

echo -e "${CYAN}--- Concluído ---${NC}"
echo "Verifique os logs com: docker logs grammarly_api --tail 20"
