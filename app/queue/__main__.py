"""Entry point for running the worker as a module: python -m app.queue.consumer"""

import asyncio

from app.queue.consumer import run_worker

if __name__ == "__main__":
    asyncio.run(run_worker())

