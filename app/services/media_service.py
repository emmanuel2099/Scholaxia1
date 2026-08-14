"""
Media Service — Cloudinary
--------------------------
All file uploads (books, videos, notes, assignment images) go through Cloudinary.

Book DRM rules enforced here:
  - Books are uploaded to a private Cloudinary folder
  - Read URLs are signed and expire in 30 minutes
  - ContentDisposition=inline prevents download triggers
  - Raw public_id is never sent to the client
"""

import uuid
import cloudinary
import cloudinary.uploader
import cloudinary.utils
from app.core.config import settings

# Configure Cloudinary once on import
cloudinary.config(
    cloud_name=settings.CLOUDINARY_CLOUD_NAME,
    api_key=settings.CLOUDINARY_API_KEY,
    api_secret=settings.CLOUDINARY_API_SECRET,
    secure=True,
)

ALLOWED_CONTENT_TYPES = {
    "books": ["application/pdf"],
    "videos": ["video/mp4", "video/webm"],
    "notes": ["application/pdf"],
    "images": ["image/jpeg", "image/png", "image/webp"],
    "assignments": ["application/pdf", "image/jpeg", "image/png"],
}

# Cloudinary resource types per folder
FOLDER_RESOURCE_TYPE = {
    "books": "raw",       # PDFs are "raw" in Cloudinary
    "notes": "raw",
    "assignments": "raw",
    "videos": "video",
    "images": "image",
    "covers": "image",
    "snapshots": "image",
    "cbt": "image",
    "marketplace": "image",
    "marketplace_files": "raw",
}


def _file_extension(filename: str | None, folder: str) -> str:
    name = (filename or "").rsplit("/", 1)[-1].rsplit("\\", 1)[-1].lower()
    if "." in name:
        ext = "." + name.rsplit(".", 1)[-1]
        if 1 < len(ext) <= 8 and ext[1:].isalnum():
            return ext
    if folder in ("books", "notes"):
        return ".pdf"
    return ""


def get_upload_params(folder: str, filename: str | None = None) -> dict:
    """
    Returns Cloudinary upload parameters for a given folder.
    Books and notes use type='authenticated' so URLs require signing.
    Other assets use type='upload' (public).
    """
    resource_type = FOLDER_RESOURCE_TYPE.get(folder, "raw")
    public_id = f"scholaxia/{folder}/{uuid.uuid4().hex}{_file_extension(filename, folder)}"

    if folder in ("books", "notes"):
        # Private — requires signed URL to access
        return {
            "public_id": public_id,
            "resource_type": resource_type,
            "type": "authenticated",   # access-controlled
            "overwrite": False,
        }

    return {
        "public_id": public_id,
        "resource_type": resource_type,
        "type": "upload",
        "overwrite": False,
    }


def upload_file(file_bytes: bytes, folder: str, filename: str | None = None) -> dict:
    """
    Upload a file to Cloudinary.
    Returns public_id (stored in DB) and the delivery URL.
    """
    from io import BytesIO

    params = get_upload_params(folder, filename)
    buffer = BytesIO(file_bytes)
    # Cloudinary uses .name to detect PDF vs image. A nameless buffer is treated as an image.
    buffer.name = filename or ("book.pdf" if folder in ("books", "notes") else "upload.bin")
    result = cloudinary.uploader.upload(buffer, **params)
    secure = result.get("secure_url") or result.get("url") or ""
    if secure.startswith("http://"):
        secure = "https://" + secure[len("http://") :]
    return {
        "public_id": result["public_id"],
        "resource_type": result["resource_type"],
        "secure_url": secure,
        "url": secure,
    }


def generate_read_url(public_id: str, expires_in_seconds: int = 1800) -> str:
    """
    Generate a short-lived signed URL for reading a book inside the app.

    Rules:
    - Signed URL expires in 30 minutes — useless after that
    - attachment=False means inline rendering, not a download
    - The raw public_id is never sent to the client
    """
    import time
    expire_at = int(time.time()) + expires_in_seconds

    url, _ = cloudinary.utils.cloudinary_url(
        public_id,
        resource_type="raw",
        type="authenticated",
        sign_url=True,
        expires_at=expire_at,
        attachment=False,   # inline — no download trigger
        secure=True,
    )
    return url


def generate_upload_signature(folder: str) -> dict:
    """
    Generate a signed upload signature for direct client-side upload to Cloudinary.
    The client uploads directly to Cloudinary using this signature — file never passes through our server.
    Returns everything the frontend needs to POST to Cloudinary's upload endpoint.
    """
    import time
    params = get_upload_params(folder)
    timestamp = int(time.time())

    signature = cloudinary.utils.api_sign_request(
        {
            "timestamp": timestamp,
            "public_id": params["public_id"],
            "type": params.get("type", "upload"),
        },
        settings.CLOUDINARY_API_SECRET,
    )

    return {
        "cloud_name": settings.CLOUDINARY_CLOUD_NAME,
        "api_key": settings.CLOUDINARY_API_KEY,
        "timestamp": timestamp,
        "public_id": params["public_id"],
        "signature": signature,
        "resource_type": params["resource_type"],
        "type": params.get("type", "upload"),
        # Frontend POSTs to: https://api.cloudinary.com/v1_1/{cloud_name}/{resource_type}/upload
    }
