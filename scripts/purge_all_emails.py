"""One-off script: delete all student/teacher/kind emails from the database."""
import asyncio
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from app.core.database import AsyncSessionLocal
from app.services.user_cleanup import purge_all_user_accounts


async def main():
    async with AsyncSessionLocal() as db:
        result = await purge_all_user_accounts(db)
        await db.commit()
    print("Purged user accounts:", result)


if __name__ == "__main__":
    asyncio.run(main())
