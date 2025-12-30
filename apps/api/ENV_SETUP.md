# API Environment Configuration

## ⚠️ IMPORTANT: Docker vs Local Development

### Docker Deployment (Production/Server)

**DO NOT create a `.env` file when using Docker!**

All environment variables are set in:
- `docker-compose.yml` (root directory)

The `.dockerignore` file prevents `.env` from being copied into containers.

### Local Development (Without Docker)

For local development, create `.env` with:

```env
NODE_ENV=development
PORT=3003
DATABASE_URL=postgresql://postgres:postgres@localhost:5434/grammarly_clone
REDIS_URL=redis://localhost:6381
JWT_SECRET=your-super-secret-jwt-key-min-32-characters
AI_PROVIDER=groq
GROQ_API_KEY=your-key-here
CORS_ORIGIN=http://localhost:5173
```

## Common Issues

### Problem: API can't connect to database in Docker

**Symptom:** "Authentication failed against database server"

**Cause:** `.env` file exists and overrides Docker Compose variables

**Solution:**
```bash
# Remove .env from API directory
rm apps/api/.env

# Rebuild container
docker compose up -d --build api
```
