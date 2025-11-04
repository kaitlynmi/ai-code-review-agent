-- Add job tracking fields to pull_requests table
ALTER TABLE pull_requests 
ADD COLUMN IF NOT EXISTS job_id VARCHAR(36),
ADD COLUMN IF NOT EXISTS enqueued_at TIMESTAMP,
ADD COLUMN IF NOT EXISTS processing_started_at TIMESTAMP,
ADD COLUMN IF NOT EXISTS completed_at TIMESTAMP,
ADD COLUMN IF NOT EXISTS attempt_count INT DEFAULT 0;

-- Update status enum to include new states
-- Note: PostgreSQL doesn't have native ENUM, so we use VARCHAR with CHECK constraint
-- Status values: pending, queued, processing, completed, failed, dead_letter

-- Add index on job_id for faster lookups
CREATE INDEX IF NOT EXISTS idx_pull_requests_job_id ON pull_requests(job_id);

-- Add index on status and enqueued_at for querying pending jobs
CREATE INDEX IF NOT EXISTS idx_pull_requests_status_enqueued ON pull_requests(status, enqueued_at);

