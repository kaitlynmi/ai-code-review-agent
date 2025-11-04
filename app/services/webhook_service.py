"""Webhook processing service."""

from app.core.logging import get_logger
from app.db.connection import get_db_pool
from app.queue.producer import enqueue_review_job

logger = get_logger(__name__)


class WebhookService:
    """Service for processing GitHub webhooks."""
    
    @staticmethod
    async def process_pull_request(payload: dict) -> dict:
        """
        Process pull request webhook payload.
        
        Args:
            payload: GitHub webhook payload dictionary
            
        Returns:
            Dictionary with processed PR information
        """
        try:
            # Extract PR information
            pull_request = payload.get("pull_request", {})
            repository = payload.get("repository", {})
            
            pr_number = pull_request.get("number")
            repo_full_name = repository.get("full_name")
            
            if not pr_number or not repo_full_name:
                raise ValueError("Missing required fields: pr_number or repo_full_name")
            
            # Store or update PR in database
            pr_id = await WebhookService._store_pr_metadata(
                pr_number=pr_number,
                repo_full_name=repo_full_name,
            )
            
            # Enqueue job for async processing
            job_id = await enqueue_review_job(
                pr_id=pr_id,
                pr_number=pr_number,
                repo_full_name=repo_full_name,
                metadata={
                    "webhook_received_at": pull_request.get("created_at", ""),
                    "action": payload.get("action", ""),
                },
            )
            
            # Update PR with job_id and status
            await WebhookService._update_pr_with_job(pr_id, job_id)
            
            return {
                "pr_id": pr_id,
                "pr_number": pr_number,
                "repo_full_name": repo_full_name,
                "job_id": job_id,
            }
            
        except Exception as e:
            logger.error(f"Error processing pull request: {e}", exc_info=True)
            raise
    
    @staticmethod
    async def _store_pr_metadata(pr_number: int, repo_full_name: str) -> int:
        """
        Store or update pull request metadata in database.
        
        Args:
            pr_number: Pull request number
            repo_full_name: Repository full name (owner/repo)
            
        Returns:
            Database ID of the pull request record
        """
        pool = await get_db_pool()
        
        async with pool.acquire() as conn:
            # Try to get existing PR
            existing = await conn.fetchrow(
                """
                SELECT id, status FROM pull_requests
                WHERE repo_full_name = $1 AND pr_number = $2
                """,
                repo_full_name,
                pr_number,
            )
            
            if existing:
                # Update existing PR
                await conn.execute(
                    """
                    UPDATE pull_requests
                    SET status = 'queued', updated_at = NOW()
                    WHERE id = $1
                    """,
                    existing["id"],
                )
                logger.info(
                    f"Updated PR #{pr_number} in {repo_full_name} "
                    f"(id: {existing['id']})"
                )
                return existing["id"]
            else:
                # Insert new PR
                pr_id = await conn.fetchval(
                    """
                    INSERT INTO pull_requests (pr_number, repo_full_name, status)
                    VALUES ($1, $2, 'queued')
                    RETURNING id
                    """,
                    pr_number,
                    repo_full_name,
                )
                logger.info(
                    f"Created new PR #{pr_number} in {repo_full_name} "
                    f"(id: {pr_id})"
                )
                return pr_id
    
    @staticmethod
    async def _update_pr_with_job(pr_id: int, job_id: str) -> None:
        """Update PR with job_id and enqueued timestamp."""
        pool = await get_db_pool()
        
        async with pool.acquire() as conn:
            await conn.execute(
                """
                UPDATE pull_requests
                SET job_id = $1, enqueued_at = NOW(), status = 'queued'
                WHERE id = $2
                """,
                job_id,
                pr_id,
            )

