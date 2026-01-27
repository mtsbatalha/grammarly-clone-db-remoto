#!/bin/sh
set -e

echo "🚀 Starting Grammarly Clone API..."

# Debug: Show masked DATABASE_URL
echo "📊 DATABASE_URL: $(echo "$DATABASE_URL" | sed 's/:\/\/[^:]*:[^@]*@/:\/\/***:***@/')"

# Auto-sync database schema (creates tables if they don't exist)
echo "📦 Syncing database schema..."
if npx prisma db push --skip-generate 2>&1; then
    echo "✅ Database schema synchronized"
else
    echo "⚠️ Database sync failed (may already be in sync or connection issue)"
fi

echo "✅ Starting API server..."
exec node dist/index.js
