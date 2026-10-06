#!/bin/bash
# Deploys the latest master on the VPS. Run from the repository root on the server.

set -euo pipefail

cd "$(dirname "$0")"

COMPOSE="docker compose -f docker-compose.prod.yml"

echo "🚀 Deploying polybot..."

git pull --ff-only origin master

# Rebuild and replace the app container; the database container keeps running.
$COMPOSE up -d --build

echo "✅ Deploy complete"
echo "📋 Logs: $COMPOSE logs -f app"
