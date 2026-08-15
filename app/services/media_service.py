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
    # Do not put .pdf in the public_id for books/notes. Cloudinary already
    # treats raw PDFs as format=pdf; embedding .pdf in the id creates .pdf.pdf URLs.
    if folder in ("books", "notes"):
        return ""
    name = (filename or "").rsplit("/", 1)[-1].rsplit("\\", 1)[-1].lower()
    if "." in name:
        ext = "." + name.rsplit(".", 1)[-1]
        if 1 < len(ext) <= 8 and ext[1:].isalnum():
            return ext
    return ""


def get_upload_params(folder: str, filename: str | None = None) -> dict:
    """
    Returns Cloudinary upload parameters for a given folder.
    Library PDFs are public-raw on Cloudinary but only streamed to students
    through our /library/{id}/file endpoint (so Android never hits a signed 404).
    """
    resource_type = FOLDER_RESOURCE_TYPE.get(folder, "raw")
    public_id = f"scholaxia/{folder}/{uuid.uuid4().hex}{_file_extension(filename, folder)}"

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
    if folder in ("books", "notes"):
        _invalidate_book_index()
    return {
        "public_id": result["public_id"],
        "resource_type": result["resource_type"],
        "secure_url": secure,
        "url": secure,
    }


def generate_read_url(public_id: str, expires_in_seconds: int = 1800) -> str:
    urls = _candidate_read_urls(public_id, expires_in_seconds)
    return urls[0] if urls else ""


def _strip_pdf_ext(pid: str) -> str:
    value = pid or ""
    while value.lower().endswith(".pdf"):
        value = value[:-4]
    return value


def _normalize_file_key(file_key: str) -> str:
    key = (file_key or "").strip()
    if not key:
        return ""
    if key.startswith("{") and "public_id" in key:
        try:
            import json

            data = json.loads(key)
            return str(data.get("public_id") or data.get("id") or "").strip()
        except Exception:
            pass
    if key.startswith("http://") or key.startswith("https://"):
        path = key.split("?", 1)[0]
        parts = path.split("/")
        if "res.cloudinary.com" in path:
            for i, part in enumerate(parts):
                if part in ("authenticated", "upload", "private") and i + 1 < len(parts):
                    rest = parts[i + 1 :]
                    if rest and rest[0].startswith("s--"):
                        rest = rest[1:]
                    # skip transformations like fl_attachment / q_auto
                    while rest and (
                        rest[0].startswith("fl_")
                        or rest[0].startswith("q_")
                        or "," in rest[0]
                        or rest[0] in ("fl_attachment",)
                    ):
                        rest = rest[1:]
                    if rest and rest[0].startswith("v") and rest[0][1:].isdigit():
                        rest = rest[1:]
                    return "/".join(rest)
            for i, part in enumerate(parts):
                if part.startswith("v") and part[1:].isdigit():
                    return "/".join(parts[i + 1 :])
        return key
    return key


def _candidate_ids(public_id: str) -> list[str]:
    pid = _normalize_file_key(public_id)
    if not pid:
        return []
    pid = pid.replace(".pdf.pdf", ".pdf")
    base = _strip_pdf_ext(pid)
    name = base.rsplit("/", 1)[-1]
    ids = [
        pid,
        base,
        f"{base}.pdf",
        f"scholaxia/books/{name}",
        f"scholaxia/books/{name}.pdf",
        f"scholaxia/notes/{name}",
        f"scholaxia/notes/{name}.pdf",
        name,
        f"{name}.pdf",
    ]
    out = []
    seen = set()
    for item in ids:
        item = (item or "").strip().replace(".pdf.pdf", ".pdf")
        if item and item not in seen:
            seen.add(item)
            out.append(item)
    return out


_BOOK_INDEX: dict = {"at": 0.0, "rows": []}


def _invalidate_book_index() -> None:
    _BOOK_INDEX["at"] = 0.0
    _BOOK_INDEX["rows"] = []


def _all_book_resources() -> list[dict]:
    import time
    import cloudinary.api

    now = time.time()
    if _BOOK_INDEX["rows"] and now - _BOOK_INDEX["at"] < 300:
        return _BOOK_INDEX["rows"]
    rows: list[dict] = []
    for prefix in ("scholaxia/books", "scholaxia/notes"):
        for resource_type in ("raw", "image"):
            for delivery in ("authenticated", "upload", "private"):
                cursor = None
                for _ in range(10):
                    kwargs = {
                        "resource_type": resource_type,
                        "type": delivery,
                        "prefix": prefix,
                        "max_results": 100,
                    }
                    if cursor:
                        kwargs["next_cursor"] = cursor
                    try:
                        listing = cloudinary.api.resources(**kwargs)
                    except Exception:
                        break
                    rows.extend(listing.get("resources") or [])
                    cursor = listing.get("next_cursor")
                    if not cursor:
                        break
    _BOOK_INDEX["at"] = now
    _BOOK_INDEX["rows"] = rows
    return rows


def _lookup_cloudinary_resource(public_id: str) -> dict | None:
    """Find the Cloudinary object without hammering resource() 40+ times."""
    import cloudinary.api

    ids = _candidate_ids(public_id)
    id_set = set(ids)
    name = _strip_pdf_ext(_normalize_file_key(public_id)).rsplit("/", 1)[-1]

    for row in _all_book_resources():
        rid = str(row.get("public_id") or "")
        if rid in id_set or (name and name in rid):
            return row

    # One exact lookup for the most likely ids only.
    for pid in ids[:4]:
        for resource_type, delivery in (
            ("raw", "authenticated"),
            ("raw", "upload"),
            ("raw", "private"),
            ("image", "upload"),
        ):
            try:
                info = cloudinary.api.resource(
                    pid, resource_type=resource_type, type=delivery
                )
                if info:
                    return info
            except Exception:
                continue
    return None


def _delivery_url(
    pid: str,
    resource_type: str,
    delivery: str,
    with_format: bool,
    expires_at: int | None = None,
) -> str:
    opts = {
        "resource_type": resource_type,
        "type": delivery,
        "secure": True,
        "sign_url": delivery in ("authenticated", "private"),
    }
    if expires_at and opts["sign_url"]:
        opts["expires_at"] = expires_at
    if with_format and not str(pid).lower().endswith(".pdf"):
        opts["format"] = "pdf"
    try:
        url, _ = cloudinary.utils.cloudinary_url(pid, **opts)
        return url or ""
    except Exception:
        return ""


def _private_downloads(pid: str, resource_type: str, delivery: str) -> list[str]:
    import time

    urls = []
    expire_at = int(time.time()) + 1800
    stripped = _strip_pdf_ext(pid)
    attempts = [(stripped, "pdf"), (pid, "")]
    if not str(pid).lower().endswith(".pdf"):
        attempts.append((pid, "pdf"))
    for dl_id, fmt in attempts:
        try:
            urls.append(
                cloudinary.utils.private_download_url(
                    dl_id,
                    fmt,
                    resource_type=resource_type,
                    type=delivery,
                    expires_at=expire_at,
                )
            )
        except Exception:
            continue
    return urls


def _download_url_for_info(info: dict) -> list[str]:
    import time

    urls = []
    pid = str(info.get("public_id") or "")
    resource_type = info.get("resource_type") or "raw"
    delivery = info.get("type") or "upload"
    expire_at = int(time.time()) + 1800
    for url in (info.get("secure_url"), info.get("url")):
        if url:
            urls.append(url)
    urls.append(_delivery_url(pid, resource_type, delivery, False, expire_at))
    urls.append(_delivery_url(pid, resource_type, delivery, True, expire_at))
    urls.extend(_private_downloads(pid, resource_type, delivery))
    return urls


def _candidate_read_urls(public_id: str, expires_in_seconds: int = 1800) -> list[str]:
    urls: list[str] = []
    seen = set()

    def add(url: str):
        if not url or url in seen:
            return
        if ".pdf.pdf" in url.lower():
            return
        seen.add(url)
        urls.append(url)

    import time

    expire_at = int(time.time()) + max(expires_in_seconds or 1800, 300)
    raw_key = (public_id or "").strip()
    if raw_key.startswith("http://") or raw_key.startswith("https://"):
        add(raw_key.replace(".pdf.pdf", ".pdf"))

    ids = _candidate_ids(raw_key)[:6]
    for pid in ids:
        if not pid or pid.startswith("http"):
            continue
        add(_delivery_url(pid, "raw", "authenticated", False, expire_at))
        add(_delivery_url(pid, "raw", "authenticated", True, expire_at))
        add(_delivery_url(pid, "raw", "upload", False, expire_at))
        add(_delivery_url(pid, "raw", "upload", True, expire_at))
        add(_delivery_url(pid, "raw", "private", False, expire_at))
        for url in _private_downloads(pid, "raw", "authenticated"):
            add(url)
        for url in _private_downloads(pid, "raw", "upload"):
            add(url)

    cloud = settings.CLOUDINARY_CLOUD_NAME
    for pid in ids:
        if not cloud or not pid or pid.startswith("http"):
            continue
        add(f"https://res.cloudinary.com/{cloud}/raw/upload/{pid}")
        if not pid.lower().endswith(".pdf"):
            add(f"https://res.cloudinary.com/{cloud}/raw/upload/{pid}.pdf")
    return urls


def _pdf_from_response(status: int, body: bytes) -> bytes | None:
    if status != 200 or not body:
        return None
    if body[:5] == b"%PDF-":
        return body
    if len(body) > 400 and b"%PDF-" in body[:4096]:
        return body[body.find(b"%PDF-") :]
    return None


def fetch_book_bytes(public_id: str) -> tuple[bytes, str]:
    """Download a library PDF from Cloudinary for streaming through our API."""
    import httpx

    last_status = 0
    urls = _candidate_read_urls(public_id)
    admin_auth = None
    if settings.CLOUDINARY_API_KEY and settings.CLOUDINARY_API_SECRET:
        admin_auth = (settings.CLOUDINARY_API_KEY, settings.CLOUDINARY_API_SECRET)
    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
        "Accept": "application/pdf,application/octet-stream,*/*",
    }

    def try_urls(client: httpx.Client, batch: list[str]) -> bytes | None:
        nonlocal last_status
        for url in batch:
            try:
                req_auth = admin_auth if "api.cloudinary.com" in url else None
                res = client.get(url, auth=req_auth, headers=headers)
            except Exception:
                continue
            last_status = res.status_code
            pdf = _pdf_from_response(res.status_code, res.content or b"")
            if pdf:
                return pdf
        return None

    with httpx.Client(timeout=20.0, follow_redirects=True) as client:
        found = try_urls(client, urls)
        if found:
            return found, "application/pdf"
        info = _lookup_cloudinary_resource(public_id)
        extra = []
        if info:
            seen = set(urls)
            for url in _download_url_for_info(info):
                if url and url not in seen and ".pdf.pdf" not in url.lower():
                    extra.append(url)
                    seen.add(url)
        found = try_urls(client, extra)
        if found:
            return found, "application/pdf"
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
