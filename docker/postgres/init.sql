-- Inicialização do PostgreSQL para GrammarlyClone

-- Extensões úteis
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- Configurações de performance
ALTER SYSTEM SET shared_preload_libraries = 'pg_stat_statements';
ALTER SYSTEM SET max_connections = 200;

-- Criação do schema
CREATE SCHEMA IF NOT EXISTS grammarly;
