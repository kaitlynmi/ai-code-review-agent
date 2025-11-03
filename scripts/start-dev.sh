#!/bin/bash
# Development startup script with Docker Compose management

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

export PATH="$HOME/.local/bin:$PATH"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}🚀 Starting AI Code Review Agent Development Environment${NC}"

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
echo -e "${YELLOW}🐳 Starting Docker Compose services (PostgreSQL & Redis)...${NC}"
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

if [ $WAITED -eq $MAX_WAIT ]; then
    echo -e "${YELLOW}⚠️  Services may not be fully ready, but continuing...${NC}"
fi

# Check if .env exists
if [ ! -f .env ]; then
    echo -e "${YELLOW}⚠️  .env file not found. Creating from template...${NC}"
    cat > .env << 'EOF'
# Database
DATABASE_URL=postgresql://user:password@localhost:5432/code_review_db

# Redis
REDIS_URL=redis://localhost:6379/0

# GitHub
GITHUB_WEBHOOK_SECRET=your_webhook_secret_here
GITHUB_TOKEN=your_github_token_here

# OpenAI
OPENAI_API_KEY=your_openai_api_key_here

# App Settings
LOG_LEVEL=INFO
ENVIRONMENT=development
EOF
    echo -e "${YELLOW}⚠️  Please update .env with your actual API keys${NC}"
fi

# Start FastAPI application
echo -e "${GREEN}🚀 Starting FastAPI application...${NC}"
echo -e "${GREEN}📖 API docs will be available at: http://localhost:8000/docs${NC}"
echo -e "${GREEN}❤️  Health check: http://localhost:8000/health${NC}"
echo ""

poetry run uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

