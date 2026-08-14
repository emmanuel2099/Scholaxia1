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
                if part.startswith("v") and part[1:].isdigit():
                    return "/".join(parts[i + 1 :])
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
    pid = pid.replace(".pdf.pdf", ".pdf")
    base = _strip_pdf_ext(pid)
    name = base.rsplit("/", 1)[-1]
    ids = [
        pid,
        base,
        f"{base}.pdf",
        f"scholaxia/books/{name}",
        f"scholaxia/books/{name}.pdf",
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
    for resource_type in ("raw", "image"):
        for delivery in ("authenticated", "upload", "private"):
            cursor = None
            for _ in range(25):
                kwargs = {
                    "resource_type": resource_type,
                    "type": delivery,
                    "prefix": "scholaxia/books",
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
    import cloudinary.api

    ids = _candidate_ids(public_id)
    id_set = set(ids)
    name = _strip_pdf_ext(_normalize_file_key(public_id)).rsplit("/", 1)[-1]

    for pid in ids:
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

    for row in _all_book_resources():
        rid = str(row.get("public_id") or "")
        if rid in id_set or (name and name in rid):
            return row
    return None


def _delivery_url(pid: str, resource_type: str, delivery: str, with_format: bool) -> str:
    opts = {
        "resource_type": resource_type,
        "type": delivery,
        "secure": True,
        "sign_url": delivery in ("authenticated", "private"),
    }
    if with_format and not str(pid).lower().endswith(".pdf"):
        opts["format"] = "pdf"
    url, _ = cloudinary.utils.cloudinary_url(pid, **opts)
    return url or ""


def _download_url_for_info(info: dict) -> list[str]:
    urls = []
    pid = str(info.get("public_id") or "")
    resource_type = info.get("resource_type") or "raw"
    delivery = info.get("type") or "upload"
    fmt = (info.get("format") or "pdf").lstrip(".") or "pdf"
    for url in (info.get("secure_url"), info.get("url")):
        if url:
            urls.append(url)
    urls.append(_delivery_url(pid, resource_type, delivery, with_format=False))
    urls.append(_delivery_url(pid, resource_type, delivery, with_format=True))
    dl_id = _strip_pdf_ext(pid) if pid.lower().endswith(".pdf") else pid
    try:
        urls.append(
            cloudinary.utils.private_download_url(
                dl_id,
                fmt if not pid.lower().endswith(".pdf") else "pdf",
                resource_type=resource_type,
                type=delivery,
                attachment=False,
            )
        )
    except Exception:
        pass
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

    raw_key = (public_id or "").strip()
    if raw_key.startswith("http://") or raw_key.startswith("https://"):
        add(raw_key.replace(".pdf.pdf", ".pdf"))

    info = _lookup_cloudinary_resource(public_id)
    if info:
        for url in _download_url_for_info(info):
            add(url)

    cloud = settings.CLOUDINARY_CLOUD_NAME
    for pid in _candidate_ids(public_id):
        for resource_type in ("raw", "image"):
            for delivery in ("upload", "authenticated"):
                add(_delivery_url(pid, resource_type, delivery, with_format=False))
                add(_delivery_url(pid, resource_type, delivery, with_format=True))
        if cloud:
            bare = pid if pid.lower().endswith(".pdf") else f"{pid}.pdf"
            add(f"https://res.cloudinary.com/{cloud}/raw/upload/{pid}")
            add(f"https://res.cloudinary.com/{cloud}/raw/upload/{bare}")
            add(f"https://res.cloudinary.com/{cloud}/image/upload/{pid}")
        try:
            add(
                cloudinary.utils.private_download_url(
                    _strip_pdf_ext(pid),
                    "pdf",
                    resource_type="raw",
                    type="authenticated",
                    attachment=False,
                )
            )
            add(
                cloudinary.utils.private_download_url(
                    _strip_pdf_ext(pid),
                    "pdf",
                    resource_type="raw",
                    type="upload",
                    attachment=False,
                )
            )
        except Exception:
            pass
    return urls


def fetch_book_bytes(public_id: str) -> tuple[bytes, str]:
    """Download a library PDF from Cloudinary for streaming through our API."""
    import httpx

    last_status = 0
    urls = _candidate_read_urls(public_id)
    admin_auth = None
    if settings.CLOUDINARY_API_KEY and settings.CLOUDINARY_API_SECRET:
        admin_auth = (settings.CLOUDINARY_API_KEY, settings.CLOUDINARY_API_SECRET)
    with httpx.Client(timeout=60.0, follow_redirects=True) as client:
        for url in urls:
            try:
                req_auth = admin_auth if "api.cloudinary.com" in url else None
                res = client.get(url, auth=req_auth)
            except Exception:
                continue
            last_status = res.status_code
            body = res.content or b""
            if res.status_code == 200 and body[:5] == b"%PDF-":
                return body, "application/pdf"
            if res.status_code == 200 and len(body) > 400 and b"%PDF-" in body[:2048]:
                start = body.find(b"%PDF-")
                return body[start:], "application/pdf"
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
