#!/bin/bash
# RAGFlow Development Mode - Restart Script
# This script restarts RAGFlow containers with local code mounted

echo "🔄 Restarting RAGFlow in development mode..."
echo "📂 Local code will be mounted into containers"

cd "$(dirname "$0")"

# Stop containers
echo "⏹️  Stopping containers..."
docker-compose down

# Start containers
echo "🚀 Starting containers..."
docker-compose up -d

# Wait a moment for containers to start
sleep 3

# Show container status
echo ""
echo "📊 Container status:"
docker-compose ps

echo ""
echo "✅ Done! Your code changes in /api, /rag, /deepdoc, /agent, /graphrag, /agentic_reasoning are now live!"
echo "📝 View logs: docker-compose logs -f ragflow"
echo "🔍 Check specific service: docker exec -it ragflow-server bash"



