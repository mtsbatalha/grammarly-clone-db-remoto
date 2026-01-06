#!/bin/sh
set -e

echo "🚀 Starting Grammarly Clone API..."

# Debug: Show masked DATABASE_URL
echo "📊 DATABASE_URL: $(echo "$DATABASE_URL" | sed 's/:\/\/[^:]*:[^@]*@/:\/\/***:***@/')"

echo "✅ Starting API server..."
exec node dist/index.js

