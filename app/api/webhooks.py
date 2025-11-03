"""GitHub webhook endpoints."""

import hmac
import hashlib
import json

from fastapi import APIRouter, Header, HTTPException, Request, status
from fastapi.responses import JSONResponse

from app.core.config import settings
from app.core.logging import get_logger
from app.services.webhook_service import WebhookService

logger = get_logger(__name__)
router = APIRouter()


def verify_signature(payload: bytes, signature: str, secret: str) -> bool:
    """
    Verify GitHub webhook signature using HMAC SHA-256.
    
    Args:
        payload: Raw request body as bytes
        signature: X-Hub-Signature-256 header value
        secret: Webhook secret from configuration
        
    Returns:
        True if signature is valid, False otherwise
    """
    if not signature or not secret:
        # In development, allow requests without signature if secret is not configured
        if settings.environment == "development" and secret == "your_webhook_secret_here":
            logger.warning("Skipping signature verification in development mode")
            return True
        return False
    
    # GitHub sends signature in format: sha256=<hex_digest>
    if not signature.startswith("sha256="):
        return False
    
    # Extract the hex digest
    received_digest = signature[7:]
    
    # Calculate expected signature
    expected_digest = hmac.new(
        secret.encode(), payload, hashlib.sha256
    ).hexdigest()
    
    # Use constant-time comparison to prevent timing attacks
    return hmac.compare_digest(received_digest, expected_digest)


@router.post("/github")
async def github_webhook(
    request: Request,
    x_hub_signature_256: str = Header(None, alias="X-Hub-Signature-256"),
    x_github_event: str = Header(None, alias="X-GitHub-Event"),
):
    """
    Handle GitHub webhook events.
    
    Currently handles:
    - pull_request events (opened, synchronize, reopened)
    
    Args:
        request: FastAPI request object
        x_hub_signature_256: GitHub webhook signature header
        x_github_event: GitHub event type header
        
    Returns:
        JSON response with processing status
    """
    try:
        # Read raw body for signature verification
        body = await request.body()
        
        # Verify signature
        if not verify_signature(body, x_hub_signature_256, settings.github_webhook_secret):
            logger.warning("Invalid webhook signature")
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid signature"
            )
        
        # Parse JSON payload
        try:
            payload = json.loads(body.decode("utf-8"))
        except json.JSONDecodeError as e:
            logger.error(f"Invalid JSON payload: {e}")
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid JSON payload"
            )
        
        # Only process pull_request events
        if x_github_event != "pull_request":
            logger.info(f"Ignoring event type: {x_github_event}")
            return JSONResponse(
                status_code=status.HTTP_200_OK,
                content={"message": f"Event type '{x_github_event}' ignored"}
            )
        
        # Process pull request webhook
        action = payload.get("action")
        if action not in ["opened", "synchronize", "reopened"]:
            logger.info(f"Ignoring pull_request action: {action}")
            return JSONResponse(
                status_code=status.HTTP_200_OK,
                content={"message": f"Action '{action}' ignored"}
            )
        
        # Process the webhook
        result = await WebhookService.process_pull_request(payload)
        
        logger.info(
            f"Processed PR #{result['pr_number']} from {result['repo_full_name']} "
            f"(action: {action}, pr_id: {result.get('pr_id')})"
        )
        
        return JSONResponse(
            status_code=status.HTTP_200_OK,
            content={
                "message": "Webhook processed successfully",
                "pr_id": result.get("pr_id"),
                "pr_number": result["pr_number"],
                "repo_full_name": result["repo_full_name"],
                "action": action,
            }
        )
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error processing webhook: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Internal server error: {str(e)}"
        )

