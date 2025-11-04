#!/bin/bash
# Quick test script for Job Queue System

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}🧪 Testing Job Queue System${NC}"
echo "============================"

# Check if services are running
echo ""
echo -e "${YELLOW}1. Checking services...${NC}"

if ! curl -s http://localhost:8000/health > /dev/null; then
    echo -e "${RED}❌ FastAPI is not running. Start it with: ./scripts/start-dev.sh${NC}"
    exit 1
fi

if ! docker ps | grep -q code_review_redis; then
    echo -e "${RED}❌ Redis is not running. Start it with: docker-compose up -d${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Services are running${NC}"

# Get webhook secret from .env
if [ ! -f .env ]; then
    echo -e "${RED}❌ .env file not found${NC}"
    exit 1
fi

SECRET=$(grep GITHUB_WEBHOOK_SECRET .env | cut -d '=' -f2 | tr -d '"' | tr -d "'")
if [ -z "$SECRET" ] || [ "$SECRET" = "your_webhook_secret_here" ]; then
    echo -e "${YELLOW}⚠️  Using default secret for testing${NC}"
    SECRET="test_secret"
fi

# Generate test PR number
PR_NUMBER=$((RANDOM % 10000 + 2000))

echo ""
echo -e "${YELLOW}2. Sending test webhook (PR #$PR_NUMBER)...${NC}"

PAYLOAD="{\"action\":\"opened\",\"pull_request\":{\"number\":$PR_NUMBER,\"title\":\"Test PR\"},\"repository\":{\"full_name\":\"test/repo\"}}"
SIGNATURE=$(echo -n "$PAYLOAD" | openssl dgst -sha256 -hmac "$SECRET" 2>/dev/null | sed 's/^.* //' || echo "test_signature")
SIGNATURE="sha256=$SIGNATURE"

RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST http://localhost:8000/webhooks/github \
  -H "Content-Type: application/json" \
  -H "X-Hub-Signature-256: $SIGNATURE" \
  -H "X-GitHub-Event: pull_request" \
  -d "$PAYLOAD")

HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP_CODE" | cut -d ':' -f2)
BODY=$(echo "$RESPONSE" | sed '/HTTP_CODE/d')

if [ "$HTTP_CODE" = "200" ]; then
    echo -e "${GREEN}✅ Webhook accepted${NC}"
    JOB_ID=$(echo "$BODY" | python3 -c "import sys, json; print(json.load(sys.stdin).get('job_id', 'N/A'))" 2>/dev/null || echo "N/A")
    echo "   Job ID: $JOB_ID"
else
    echo -e "${RED}❌ Webhook failed (HTTP $HTTP_CODE)${NC}"
    echo "$BODY"
    exit 1
fi

# Check queue
echo ""
echo -e "${YELLOW}3. Checking queue...${NC}"
QUEUE_LENGTH=$(docker exec code_review_redis redis-cli XLEN review_jobs 2>/dev/null || echo "0")
echo "   Queue length: $QUEUE_LENGTH"

# Check database
echo ""
echo -e "${YELLOW}4. Checking database...${NC}"
DB_STATUS=$(docker exec code_review_postgres psql -U user -d code_review_db -t -c \
  "SELECT status FROM pull_requests WHERE pr_number = $PR_NUMBER;" 2>/dev/null | tr -d ' ' || echo "NOT_FOUND")

echo "   PR #$PR_NUMBER status: $DB_STATUS"

# Wait for processing
echo ""
echo -e "${YELLOW}5. Waiting for job to be processed (10 seconds)...${NC}"
sleep 10

# Check final status
echo ""
echo -e "${YELLOW}6. Checking final status...${NC}"
FINAL_STATUS=$(docker exec code_review_postgres psql -U user -d code_review_db -t -c \
  "SELECT status FROM pull_requests WHERE pr_number = $PR_NUMBER;" 2>/dev/null | tr -d ' ' || echo "NOT_FOUND")

if [ "$FINAL_STATUS" = "completed" ]; then
    echo -e "${GREEN}✅ Job completed successfully!${NC}"
elif [ "$FINAL_STATUS" = "processing" ]; then
    echo -e "${YELLOW}⚠️  Job is still processing${NC}"
elif [ "$FINAL_STATUS" = "queued" ]; then
    echo -e "${YELLOW}⚠️  Job is still queued (worker may not be running)${NC}"
    echo "   Start worker with: ./scripts/start-worker.sh"
else
    echo -e "${RED}❌ Job status: $FINAL_STATUS${NC}"
fi

# Check metrics
echo ""
echo -e "${YELLOW}7. Queue metrics:${NC}"
curl -s http://localhost:8000/api/metrics | python3 -m json.tool 2>/dev/null || echo "Could not fetch metrics"

echo ""
echo -e "${GREEN}✅ Test completed!${NC}"
echo ""
echo "Next steps:"
echo "  - Check worker logs to see processing details"
echo "  - View metrics: curl http://localhost:8000/api/metrics"
echo "  - Check database: docker exec code_review_postgres psql -U user -d code_review_db -c \"SELECT * FROM pull_requests WHERE pr_number = $PR_NUMBER;\""

