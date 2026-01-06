#!/bin/sh
set -e

echo "🚀 Starting Grammarly Clone API..."

# Debug: Show masked DATABASE_URL
echo "📊 DATABASE_URL: $(echo "$DATABASE_URL" | sed 's/:\/\/[^:]*:[^@]*@/:\/\/***:***@/')"

echo "🔄 Syncing database schema with Prisma..."
npx prisma db push --accept-data-loss || {
    echo "❌ Failed to sync database. Retrying in 5 seconds..."
    sleep 5
    npx prisma db push --accept-data-loss
}

echo "✅ Database sync complete. Starting API..."
exec node dist/index.js
