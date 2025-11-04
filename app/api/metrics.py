"""Metrics and monitoring endpoints."""

from fastapi import APIRouter

from app.core.logging import get_logger
from app.db.connection import get_db_pool
from app.db.redis_client import get_redis

logger = get_logger(__name__)
router = APIRouter()

STREAM_NAME = "review_jobs"
CONSUMER_GROUP = "review_workers"


@router.get("/metrics")
async def get_metrics():
    """Get queue metrics and statistics."""
    try:
        redis = await get_redis()
        pool = await get_db_pool()
        
        # Get queue length
        queue_length = await redis.xlen(STREAM_NAME)
        
        # Get consumer group info
        try:
            group_info = await redis.xinfo_groups(STREAM_NAME)
        except Exception:
            group_info = []
        
        # Get pending messages
        pending_count = 0
        if group_info:
            try:
                pending_info = await redis.xpending(STREAM_NAME, CONSUMER_GROUP)
                if pending_info:
                    pending_count = pending_info.get("pending", 0)
            except Exception:
                pass
        
        # Get database statistics
        async with pool.acquire() as conn:
            stats = await conn.fetchrow(
                """
                SELECT 
                    COUNT(*) as total_prs,
                    COUNT(*) FILTER (WHERE status = 'queued') as queued,
                    COUNT(*) FILTER (WHERE status = 'processing') as processing,
                    COUNT(*) FILTER (WHERE status = 'completed') as completed,
                    COUNT(*) FILTER (WHERE status = 'failed') as failed,
                    COUNT(*) FILTER (WHERE status = 'dead_letter') as dead_letter
                FROM pull_requests
                """
            )
        
        return {
            "queue": {
                "stream_length": queue_length,
                "pending_messages": pending_count,
                "consumer_groups": len(group_info),
            },
            "database": {
                "total_prs": stats["total_prs"],
                "queued": stats["queued"],
                "processing": stats["processing"],
                "completed": stats["completed"],
                "failed": stats["failed"],
                "dead_letter": stats["dead_letter"],
            },
        }
    except Exception as e:
        logger.error(f"Error getting metrics: {e}", exc_info=True)
        return {"error": str(e)}


@router.get("/health/queue")
async def queue_health():
    """Health check for queue system."""
    try:
        redis = await get_redis()
        
        # Test Redis connection
        await redis.ping()
        
        # Check if stream exists
        try:
            stream_info = await redis.xinfo_stream(STREAM_NAME)
            return {
                "status": "healthy",
                "redis": "connected",
                "stream": "exists",
                "stream_length": stream_info.get("length", 0),
            }
        except Exception:
            return {
                "status": "healthy",
                "redis": "connected",
                "stream": "not_created_yet",
            }
    except Exception as e:
        return {
            "status": "unhealthy",
            "error": str(e),
        }

