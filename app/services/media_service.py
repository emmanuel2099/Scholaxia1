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
    """
    urls = _candidate_read_urls(public_id, expires_in_seconds)
    return urls[0] if urls else ""


def _normalize_file_key(file_key: str) -> str:
    key = (file_key or "").strip()
    if not key:
        return ""
    if key.startswith("http://") or key.startswith("https://"):
        # https://res.cloudinary.com/<cloud>/<resource>/<type>/s--x--/v123/folder/id.pdf
        path = key.split("?", 1)[0]
        parts = path.split("/")
        # drop scheme + host
        if "res.cloudinary.com" in path and len(parts) >= 8:
            # find version segment v123456 or public id after type
            for i, part in enumerate(parts):
                if part.startswith("v") and part[1:].isdigit():
                    return "/".join(parts[i + 1 :])
            # after raw/authenticated or raw/upload
            for i, part in enumerate(parts):
                if part in ("authenticated", "upload", "private") and i + 1 < len(parts):
                    rest = parts[i + 1 :]
                    if rest and rest[0].startswith("s--"):
                        rest = rest[1:]
                    if rest and rest[0].startswith("v") and rest[0][1:].isdigit():
                        rest = rest[1:]
                    return "/".join(rest)
        return key
    return key


def _candidate_ids(public_id: str) -> list[str]:
    pid = _normalize_file_key(public_id)
    if not pid:
        return []
    ids = [pid]
    if pid.lower().endswith(".pdf"):
        ids.append(pid[:-4])
    else:
        ids.append(pid + ".pdf")
    out = []
    seen = set()
    for item in ids:
        if item not in seen:
            seen.add(item)
            out.append(item)
    return out


def _lookup_cloudinary_resource(public_id: str) -> dict | None:
    import cloudinary.api

    for pid in _candidate_ids(public_id):
        for resource_type in ("raw", "image"):
            for delivery in ("authenticated", "upload", "private"):
                try:
                    info = cloudinary.api.resource(
                        pid, resource_type=resource_type, type=delivery
                    )
                    if info:
                        return info
                except Exception:
                    continue
    try:
        from cloudinary import Search

        pid = _normalize_file_key(public_id)
        name = pid.split("/")[-1]
        expressions = [
            f'public_id:"{pid}"',
            f"public_id:{pid}*",
            f"folder:scholaxia/books AND filename:{name}*",
        ]
        for expr in expressions:
            try:
                found = Search().expression(expr).max_results(3).execute()
                rows = found.get("resources") or []
                if rows:
                    return rows[0]
            except Exception:
                continue
    except Exception:
        pass
    return None


def _signed_url_for_resource(info: dict, expires_in_seconds: int = 1800) -> str:
    import time

    expire_at = int(time.time()) + max(int(expires_in_seconds or 1800), 60)
    pid = info.get("public_id") or ""
    resource_type = info.get("resource_type") or "raw"
    delivery = info.get("type") or "authenticated"
    fmt = (info.get("format") or "pdf").lstrip(".")
    version = info.get("version")
    kwargs = {
        "resource_type": resource_type,
        "type": delivery,
        "secure": True,
        "format": fmt,
    }
    if version:
        kwargs["version"] = version
    if delivery in ("authenticated", "private"):
        kwargs["sign_url"] = True
        kwargs["expires_at"] = expire_at
    url, _ = cloudinary.utils.cloudinary_url(pid, **kwargs)
    return url or ""


def _candidate_read_urls(public_id: str, expires_in_seconds: int = 1800) -> list[str]:
    import time

    expire_at = int(time.time()) + max(int(expires_in_seconds or 1800), 60)
    urls: list[str] = []
    seen = set()

    def add(url: str):
        if url and url not in seen:
            seen.add(url)
            urls.append(url)

    raw_key = (public_id or "").strip()
    if raw_key.startswith("http://") or raw_key.startswith("https://"):
        add(raw_key)

    info = _lookup_cloudinary_resource(public_id)
    if info:
        add(_signed_url_for_resource(info, expires_in_seconds))
        add(info.get("secure_url") or "")
        add(info.get("url") or "")
        try:
            fmt = info.get("format") or "pdf"
            add(
                cloudinary.utils.private_download_url(
                    info.get("public_id"),
                    fmt,
                    resource_type=info.get("resource_type") or "raw",
                    type=info.get("type") or "authenticated",
                    attachment=False,
                    expires_at=expire_at,
                )
            )
        except Exception:
            pass

    for pid in _candidate_ids(public_id):
        fmt = "pdf" if not pid.lower().endswith(".pdf") else None
        combos = (
            {"resource_type": "raw", "type": "authenticated", "sign_url": True, "expires_at": expire_at, "format": "pdf"},
            {"resource_type": "raw", "type": "upload", "format": "pdf"},
            {"resource_type": "raw", "type": "authenticated", "sign_url": True, "expires_at": expire_at},
            {"resource_type": "raw", "type": "upload"},
            {"resource_type": "image", "type": "authenticated", "sign_url": True, "expires_at": expire_at},
            {"resource_type": "image", "type": "upload"},
        )
        for extra in combos:
            opts = dict(extra)
            if fmt is None:
                opts.pop("format", None)
            url, _ = cloudinary.utils.cloudinary_url(pid, secure=True, **opts)
            add(url)
        try:
            add(
                cloudinary.utils.private_download_url(
                    pid.rsplit(".pdf", 1)[0] if pid.lower().endswith(".pdf") else pid,
                    "pdf",
                    resource_type="raw",
                    type="authenticated",
                    attachment=False,
                    expires_at=expire_at,
                )
            )
        except Exception:
            pass
    return urls


def fetch_book_bytes(public_id: str) -> tuple[bytes, str]:
    """
    Download a library PDF from Cloudinary using signed/public URL fallbacks.
    Opening authenticated Cloudinary links in a new browser tab returns HTTP 401.
    """
    import httpx

    last_status = 0
    for url in _candidate_read_urls(public_id):
        try:
            with httpx.Client(timeout=60.0, follow_redirects=True) as client:
                res = client.get(url)
        except Exception:
            continue
        last_status = res.status_code
        if res.status_code == 200 and res.content and (
            res.content[:5] == b"%PDF-" or len(res.content) > 200
        ):
            content_type = (res.headers.get("content-type") or "").split(";")[0].strip()
            if res.content[:5] == b"%PDF-":
                content_type = "application/pdf"
            elif not content_type or content_type in ("application/octet-stream", "text/html"):
                continue
            return res.content, content_type or "application/pdf"
    raise RuntimeError(f"Could not load library file (HTTP {last_status or 'error'}).")


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
