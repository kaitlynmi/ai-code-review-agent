#!/bin/bash
# Start script for the application

export PATH="$HOME/.local/bin:$PATH"

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "❌ Docker is not running. Please start Docker Desktop."
    exit 1
fi

# Start Docker Compose services if not running
echo "🐳 Starting Docker Compose services..."
docker-compose up -d

# Wait for services to be healthy
echo "⏳ Waiting for services to be ready..."
for i in {1..30}; do
    if docker-compose ps | grep -q "healthy"; then
        echo "✅ Services are ready"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "⚠️  Services may not be fully ready, but continuing..."
    fi
    sleep 1
done

# Activate poetry environment and run uvicorn
echo "🚀 Starting FastAPI application..."
poetry run uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

