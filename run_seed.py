"""Run database seed locally. Usage: python run_seed.py"""
import asyncio

from app.core.database import AsyncSessionLocal
from app.core.seed import seed_database


async def main():
    async with AsyncSessionLocal() as db:
        await seed_database(db)
    print("Seed complete.")


if __name__ == "__main__":
    asyncio.run(main())
