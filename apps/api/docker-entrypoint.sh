#!/bin/sh
set -e

echo "🔄 Waiting for PostgreSQL to be ready..."

# Extract host from DATABASE_URL
DB_HOST=$(echo "$DATABASE_URL" | sed -n 's/.*@\([^:]*\):.*/\1/p')

# Install netcat if not present (minimal Alpine/Debian)
if ! command -v nc > /dev/null 2>&1; then
    echo "   Installing netcat..."
    apt-get update -qq && apt-get install -y -qq netcat-openbsd > /dev/null 2>&1 || true
fi

# Wait for PostgreSQL to be available (max 60 seconds)
for i in $(seq 1 60); do
    if nc -z "$DB_HOST" 5432 2>/dev/null; then
        echo "✅ PostgreSQL is accepting connections!"
        break
    fi
    if [ $i -eq 60 ]; then
        echo "❌ Timeout waiting for PostgreSQL"
        exit 1
    fi
    echo "   Waiting for PostgreSQL at $DB_HOST... ($i/60)"
    sleep 1
done

# Additional wait for PostgreSQL to be fully ready
echo "🔄 Waiting for PostgreSQL to be fully ready..."
sleep 3

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
