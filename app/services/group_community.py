"""Community feed posts for listed student groups."""
import re
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.community import CommunityChannel, CommunityPost, ChannelType, PostVisibility
from app.models.student_group import StudentGroup

GROUP_POST_RE = re.compile(r"^@group:([^\s]+)(?:\s+([\s\S]*))?$")


def group_post_content(group_id: str, name: str, description: str | None) -> str:
    desc = (description or "").strip()
    tail = f" {desc}" if desc else ""
    return f"@group:{group_id}{tail}"


def parse_group_post(content: str) -> tuple[str | None, str]:
    if not content:
        return None, ""
    match = GROUP_POST_RE.match(content.strip())
    if not match:
        return None, content
    return match.group(1), (match.group(2) or "").strip()


async def ensure_group_feed_post(db: AsyncSession, group: StudentGroup) -> CommunityPost | None:
    """Create a Community feed post when a group is listed (idempotent)."""
    gid = str(group.id)
    prefix = f"@group:{gid}"
    existing = await db.execute(
        select(CommunityPost).where(
            CommunityPost.content.like(f"{prefix}%"),
            CommunityPost.is_deleted == False,  # noqa: E712
        )
    )
    if existing.scalar_one_or_none():
        return None

    ch_res = await db.execute(
        select(CommunityChannel).where(CommunityChannel.channel_type == ChannelType.general)
    )
    channel = ch_res.scalar_one_or_none()
    if not channel:
        return None

    post = CommunityPost(
        channel_id=channel.id,
        author_id=group.creator_id,
        content=group_post_content(gid, group.name, group.description),
        visibility=PostVisibility.everyone.value,
    )
    db.add(post)
    await db.flush()
    return post
