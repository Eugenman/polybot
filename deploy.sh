cat > ~/polybot/deploy.sh << 'EOF'
#!/bin/bash

set -e

echo "🚀 Deploying polybot to VPS..."

# Pull latest code
git pull origin feature/vps-deploy

# Build and restart containers
docker compose -f docker-compose.prod.yml down
docker compose -f docker-compose.prod.yml build --no-cache
docker compose -f docker-compose.prod.yml up -d

echo "✅ Deploy complete!"
echo "📋 Logs: docker compose -f docker-compose.prod.yml logs -f"
EOF

chmod +x ~/polybot/deploy.sh