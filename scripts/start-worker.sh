#!/bin/bash
# Start script for the review worker

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

export PATH="$HOME/.local/bin:$PATH"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}🚀 Starting Review Worker${NC}"

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}❌ Docker is not running. Please start Docker Desktop.${NC}"
    exit 1
fi

# Check if docker-compose is available
if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
    echo -e "${RED}❌ docker-compose is not available${NC}"
    exit 1
fi

# Use docker compose (newer) or docker-compose (older)
COMPOSE_CMD="docker compose"
if ! docker compose version &> /dev/null; then
    COMPOSE_CMD="docker-compose"
fi

# Start Docker Compose services
echo -e "${YELLOW}🐳 Ensuring Docker Compose services are running...${NC}"
$COMPOSE_CMD up -d

# Wait for services to be healthy
echo -e "${YELLOW}⏳ Waiting for services to be ready...${NC}"
MAX_WAIT=30
WAITED=0
while [ $WAITED -lt $MAX_WAIT ]; do
    if $COMPOSE_CMD ps | grep -q "healthy"; then
        echo -e "${GREEN}✅ Services are healthy${NC}"
        break
    fi
    WAITED=$((WAITED + 1))
    sleep 1
done

# Start worker
echo -e "${GREEN}👷 Starting review worker...${NC}"
echo -e "${GREEN}📝 Worker will process jobs from Redis Streams${NC}"
echo -e "${GREEN}🛑 Press Ctrl+C to stop gracefully${NC}"
echo ""

poetry run python -m app.queue.consumer

