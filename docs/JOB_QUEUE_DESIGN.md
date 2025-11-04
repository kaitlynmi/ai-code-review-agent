# Job Queue System Design

## Overview

The job queue system transforms the webhook handler from synchronous processing to asynchronous job processing using Redis Streams.

## Architecture

### Current Flow (Synchronous)
```
Webhook → Process PR → Return 200 OK
         (blocking, 2-10 seconds)
```

### Target Flow (Asynchronous)
```
Webhook → Enqueue Job → Return 200 OK (<200ms)
                           ↓
                    Redis Streams
                           ↓
                    Worker picks up → Process PR
```

## Design Decisions

### 1. Why Async Processing?

**Problem:** GitHub webhooks should respond within 200ms, but PR review takes 2-10 seconds.

**Solution:** Return immediately after enqueueing, process asynchronously.

**Benefits:**
- Fast webhook response times
- Better scalability (can handle burst traffic)
- Isolation of failures (webhook failures don't affect processing)
- Ability to retry failed jobs

### 2. Redis Streams

**Why Redis Streams?**
- Built into Redis (no additional dependencies)
- Supports consumer groups (multiple workers)
- Persistent (survives Redis restart)
- Message acknowledgment
- Blocking reads (efficient waiting)

**Stream Name:** `review_jobs`

**Consumer Group:** `review_workers`

### 3. Job Lifecycle

```
pending → queued → processing → completed
                              ↓
                           failed (retry)
                              ↓
                        dead_letter (max retries)
```

### 4. Job Data Structure

```json
{
  "job_id": "uuid-v4",
  "pr_id": 123,
  "pr_number": 456,
  "repo_full_name": "owner/repo",
  "enqueued_at": "2025-11-03T23:00:00Z",
  "attempt_count": 0,
  "status": "queued",
  "metadata": {
    "webhook_received_at": "2025-11-03T23:00:00Z"
  }
}
```

### 5. Queue Architecture

**Single Queue:** `review_jobs` stream
- All PR review jobs go to same queue
- FIFO processing (first in, first out)
- Simple to manage

**Future:** Could add priority queues if needed

### 6. Consumer Groups

**Single Consumer Group:** `review_workers`
- Multiple workers can be in same group
- Each job processed by one worker
- Automatic load balancing

**Scaling:** Add more workers to increase throughput

### 7. Retry Strategy

**Max Retries:** 3 attempts

**Backoff Strategy:** Exponential backoff
- Attempt 1: Immediate
- Attempt 2: 2 seconds
- Attempt 3: 4 seconds
- Attempt 4: 8 seconds (then move to dead letter)

**Dead Letter Queue:** `review_jobs:dead_letter`
- Jobs that fail after max retries
- Can be manually inspected and retried

### 8. Database Schema

**Option 1: Use existing `pull_requests` table**
- Add `status` field (already exists)
- Add `job_id`, `enqueued_at`, `processing_started_at`, `completed_at`
- Simple, no new tables

**Option 2: Separate `jobs` table**
- Track all job attempts
- More detailed history
- Better for auditing

**Decision: Use Option 1** (simpler, sufficient for now)

**Migration needed:**
```sql
ALTER TABLE pull_requests 
ADD COLUMN job_id VARCHAR(36),
ADD COLUMN enqueued_at TIMESTAMP,
ADD COLUMN processing_started_at TIMESTAMP,
ADD COLUMN completed_at TIMESTAMP,
ADD COLUMN attempt_count INT DEFAULT 0;
```

## Implementation Plan

### Phase 1: Basic Queue (Tasks 3.1-3.4)
1. Design and documentation ✅
2. Job data model
3. Producer (enqueue jobs)
4. Consumer (process jobs)

### Phase 2: Production Ready (Tasks 3.5-3.8)
5. Worker management (graceful shutdown)
6. Status tracking
7. Error handling and retries
8. Observability

## Error Scenarios

### 1. Redis Connection Lost
- **During enqueue:** Return error to webhook, log failure
- **During processing:** Re-enqueue job, increment retry count

### 2. Worker Crash
- **Before acknowledgment:** Job remains in stream, another worker picks it up
- **After acknowledgment:** Use job status in DB to detect stuck jobs

### 3. Processing Exception
- **Catch exception:** Log error, increment retry count
- **If retries exhausted:** Move to dead letter queue

### 4. Webhook Timeout
- **Enqueue quickly:** Should complete in <100ms
- **If Redis slow:** Return error, log for monitoring

## Monitoring

### Metrics to Track
- Queue depth (jobs waiting)
- Processing rate (jobs/minute)
- Success/failure rates
- Average processing time
- Retry statistics

### Logging
- Structured logs for all job events
- Job ID in all log entries (for tracing)
- Error details with stack traces

### Health Checks
- Redis connection status
- Queue length
- Active workers
- Failed jobs count

## Testing Strategy

1. **Unit Tests:** Producer and consumer logic
2. **Integration Tests:** End-to-end webhook → queue → worker
3. **Load Tests:** Multiple concurrent webhooks
4. **Failure Tests:** Redis down, worker crash, processing errors

## Future Enhancements

- Priority queues (urgent PRs first)
- Scheduled jobs (delay processing)
- Job deduplication (avoid duplicate reviews)
- Job cancellation (cancel in-flight jobs)
- Webhook replay (retry failed webhooks)

