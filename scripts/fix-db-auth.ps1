$root = Get-Item $PSScriptRoot
if ($root.Name -eq "scripts") { $root = $root.Parent }
Set-Location $root.FullName

Write-Host "=== Sincronizando Autenticacao do Banco de Dados ===" -ForegroundColor Cyan

# 1. Obter a senha correta do POSTGRES_PASSWORD no docker-compose.yml
$DockerComposeContent = Get-Content "docker-compose.yml" -Raw
if ($DockerComposeContent -match 'POSTGRES_PASSWORD:\s*(\S+)') {
    $CorrectPassword = $Matches[1]
    Write-Host "[OK] Senha configurada encontrada: $CorrectPassword" -ForegroundColor Green
}
else {
    Write-Error "Nao foi possivel encontrar POSTGRES_PASSWORD no docker-compose.yml"
    exit 1
}

# 2. Corrigir o DATABASE_URL se estiver errado no arquivo
$Pattern = "DATABASE_URL=postgresql://postgres:(.*)@.*postgres:5432/grammarly_clone\?schema=public"
if ($DockerComposeContent -match $Pattern) {
    $CurrentPasswordInUrl = $Matches[1]
    if ($CurrentPasswordInUrl -ne $CorrectPassword) {
        Write-Host "[!] Senha na DATABASE_URL esta divergente ($CurrentPasswordInUrl). Corrigindo..." -ForegroundColor Yellow
        $NewContent = $DockerComposeContent -replace [regex]::Escape($CurrentPasswordInUrl), $CorrectPassword
        Set-Content "docker-compose.yml" $NewContent
        Write-Host "[OK] docker-compose.yml atualizado." -ForegroundColor Green
    }
    else {
        Write-Host "[OK] Senha na DATABASE_URL ja esta correta." -ForegroundColor Green
    }
}

# 3. Remover arquivos .env residuais que causam conflitos
$EnvFilePath = Join-Path $root.FullName "apps\api\.env"
if (Test-Path $EnvFilePath) {
    Write-Host "[!] Arquivo $EnvFilePath detectado. Removendo para evitar conflitos..." -ForegroundColor Yellow
    Remove-Item $EnvFilePath -Force
    Write-Host "[OK] Arquivo removido." -ForegroundColor Green
}

# 4. Reiniciar o container da API
Write-Host "[*] Reiniciando container grammarly_api..." -ForegroundColor Cyan
docker compose up -d --build api

# 5. Forcar atualizacao da senha dentro do Postgres
Write-Host "[*] Garantindo que a senha esta aplicada no banco de dados..." -ForegroundColor Cyan
$sql = "ALTER USER postgres WITH PASSWORD '$CorrectPassword';"
# Usando -- para separar argumentos do docker dos argumentos do psql se necessario, mas aqui vamos direto
& docker exec grammarly_postgres psql -U postgres -d postgres -c "$sql"

Write-Host "=== Concluido ===" -ForegroundColor Cyan
Write-Host "Verifique os logs com: docker logs grammarly_api --tail 20"
