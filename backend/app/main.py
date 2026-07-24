import asyncio
import os
import re
import sys
import time
import urllib.parse
from typing import Optional
from anyio import to_thread

from fastapi import FastAPI, HTTPException, Depends, Header, status, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from starlette.requests import Request

import yt_dlp
import httpx
from dotenv import load_dotenv

from app.models import ExtractRequest, ExtractResponse, FormatInfo
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded

load_dotenv()

limiter = Limiter(key_func=get_remote_address)

app = FastAPI(
    title="Video Extraction Backend",
    description="Backend API for extracting and proxy-streaming video formats using yt-dlp.",
    version="1.0.0"
)

app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

startup_time = time.time()

allowed_origins = [org.strip() for org in os.getenv("ALLOWED_ORIGINS", "").split(",") if org.strip()]
if not allowed_origins:
    allowed_origins = ["http://localhost:3000"]

app.add_middleware(
    CORSMiddleware,
    allow_origins=allowed_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


async def verify_mobile_user_agent(user_agent: str = Header(None)):
    if os.getenv("DISABLE_UA_CHECK", "false").lower() == "true":
        return user_agent
    allowed_ua = os.getenv("MOBILE_USER_AGENT", "CuddleUmbrellaMobile/1.0")
    if not user_agent:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN,
                            detail="Access forbidden: Missing User-Agent header")
    ua_base = allowed_ua.split("/")[0] + "/"
    if user_agent != allowed_ua and not user_agent.startswith(ua_base):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN,
                            detail="Access forbidden: Invalid User-Agent")
    return user_agent


def sanitize_filename(title: str) -> str:
    return re.sub(r'[\\/*?:"<>|]', "", title).strip()


def get_mime_type(ext: str) -> str:
    return {
        "mp4": "video/mp4", "webm": "video/webm", "mkv": "video/x-matroska",
        "3gp": "video/3gpp", "flv": "video/x-flv", "avi": "video/x-msvideo",
        "mov": "video/quicktime", "ts": "video/MP2T",
    }.get(ext.lower(), "application/octet-stream")


def validate_video_url(url: str):
    if not url or not url.startswith(("http://", "https://")):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                            detail="Link geçersiz. URL http:// veya https:// ile başlamalıdır.")


def _is_direct_http(fmt: dict) -> bool:
    """True if yt-dlp format can be directly proxied via httpx (not a playlist/manifest)."""
    proto = (fmt.get("protocol") or "").lower()
    return "m3u8" not in proto and "dash" not in proto and "rtsp" not in proto and "rtmp" not in proto


def _extract_info_sync(url: str) -> dict:
    opts = {"noplaylist": True, "quiet": True, "no_warnings": True, "extract_flat": False}
    with yt_dlp.YoutubeDL(opts) as ydl:
        return ydl.extract_info(url, download=False)


def _build_formats(raw_formats: list, info: dict) -> list:
    """
    Build the list of FormatInfo to return to the client.

    Strategy (three passes, stop at first non-empty result):
      1. Progressive direct-HTTP: both video+audio codecs set, proxyable protocol
      2. Any video+audio (including HLS/DASH): for platforms like X that only have HLS
      3. Top-level yt-dlp selected URL fallback
    """
    def _parse_formats(fmts, require_direct_http: bool) -> list:
        best: dict[str, FormatInfo] = {}  # quality → best FormatInfo seen so far
        for fmt in fmts:
            vcodec = fmt.get("vcodec")
            acodec = fmt.get("acodec")
            has_video = vcodec is not None and vcodec != "none"
            has_audio = acodec is not None and acodec != "none"

            if not (has_video and has_audio):
                continue
            if require_direct_http and not _is_direct_http(fmt):
                continue

            h = fmt.get("height")
            w = fmt.get("width")
            res = min(h, w) if (h and w) else (h or w)
            if not res:
                continue

            quality = f"{res}p"
            filesize = fmt.get("filesize") or fmt.get("filesize_approx")
            existing = best.get(quality)
            if not existing or (filesize and (existing.filesize_approx or 0) < filesize):
                best[quality] = FormatInfo(
                    format_id=fmt.get("format_id") or "default",
                    quality=quality,
                    ext=fmt.get("ext") or "mp4",
                    filesize_approx=filesize,
                    has_audio=True,
                    has_video=True,
                )
        return sorted(best.values(),
                      key=lambda f: int(f.quality[:-1]) if f.quality[:-1].isdigit() else 0,
                      reverse=True)

    # Pass 1 – direct-HTTP progressive
    result = _parse_formats(raw_formats, require_direct_http=True)
    if result:
        return result

    # Pass 2 – any protocol (HLS, DASH, …)
    result = _parse_formats(raw_formats, require_direct_http=False)
    if result:
        return result

    # Pass 3 – top-level URL that yt-dlp selected
    url = info.get("url", "")
    if url.startswith(("http://", "https://")):
        h = info.get("height")
        w = info.get("width")
        res = min(h, w) if (h and w) else (h or w or 360)
        return [FormatInfo(
            format_id=info.get("format_id") or "default",
            quality=f"{res}p",
            ext=info.get("ext") or "mp4",
            filesize_approx=info.get("filesize") or info.get("filesize_approx"),
            has_audio=True,
            has_video=True,
        )]

    return []


# ─── 1. POST /api/extract ────────────────────────────────────────────────────

@app.post("/api/extract", response_model=ExtractResponse)
@limiter.limit("10/minute")
async def extract_video(
    request: Request,
    body: ExtractRequest,
    user_agent: str = Depends(verify_mobile_user_agent),
):
    validate_video_url(body.url)

    try:
        info = await to_thread.run_sync(_extract_info_sync, body.url)
    except yt_dlp.utils.UnsupportedError:
        raise HTTPException(status_code=400, detail="Bu platform desteklenmiyor veya link geçersiz.")
    except yt_dlp.utils.DownloadError as e:
        msg = str(e)
        if "Unsupported URL" in msg or "not a valid URL" in msg:
            raise HTTPException(status_code=400, detail="Bu platform desteklenmiyor veya link geçersiz.")
        raise HTTPException(status_code=400, detail="Link geçersiz veya video çekilemedi.")
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Video bilgisi alınamadı: {str(e)}")

    if not info:
        raise HTTPException(status_code=400, detail="Video bilgileri çözümlenemedi.")
    if "entries" in info:
        raise HTTPException(status_code=400,
                            detail="Oynatma listeleri desteklenmiyor. Lütfen tek bir video linki girin.")

    raw_formats = info.get("formats", [])
    formats_list = _build_formats(raw_formats, info) if raw_formats else []

    # Single-format fallback when there is no formats list at all
    if not formats_list and not raw_formats:
        url = info.get("url", "")
        if url.startswith(("http://", "https://")):
            h, w = info.get("height"), info.get("width")
            res = min(h, w) if (h and w) else (h or w or 360)
            formats_list = [FormatInfo(
                format_id=info.get("format_id") or "default",
                quality=f"{res}p",
                ext=info.get("ext") or "mp4",
                filesize_approx=info.get("filesize") or info.get("filesize_approx"),
                has_audio=True,
                has_video=True,
            )]

    thumbnail = info.get("thumbnail")
    if not thumbnail and info.get("thumbnails"):
        thumbnail = info["thumbnails"][-1].get("url")

    duration = info.get("duration")
    if duration is not None:
        try:
            duration = int(round(float(duration)))
        except (ValueError, TypeError):
            duration = None

    return ExtractResponse(
        title=info.get("title", "Unknown Title"),
        thumbnail=thumbnail,
        duration=duration,
        formats=formats_list,
    )


# ─── 2. GET /api/download ─────────────────────────────────────────────────────

@app.get("/api/download")
@limiter.limit("10/minute")
async def download_video(
    request: Request,
    url: str = Query(...),
    format_id: str = Query(...),
    user_agent: str = Depends(verify_mobile_user_agent),
):
    validate_video_url(url)

    try:
        info = await to_thread.run_sync(_extract_info_sync, url)
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Video bilgisi alınamadı: {str(e)}")

    # Locate the selected format
    selected_format = next(
        (f for f in info.get("formats", []) if f.get("format_id") == format_id),
        None,
    )
    if not selected_format and info.get("format_id") == format_id:
        selected_format = info
    if not selected_format:
        raise HTTPException(status_code=400, detail="Seçilen format bulunamadı veya geçersiz format ID.")

    video_url = selected_format.get("url", "")
    if not video_url:
        raise HTTPException(status_code=400, detail="Format için indirme URL'i çözümlenemedi.")

    title = info.get("title", "video")
    ext = selected_format.get("ext", "mp4")
    filename = f"{sanitize_filename(title)}.{ext}"
    encoded_filename = urllib.parse.quote(filename)
    content_disposition = f"attachment; filename*=UTF-8''{encoded_filename}"

    # ── Path A: direct HTTP stream → proxy with httpx ──────────────────────
    if _is_direct_http(selected_format) and video_url.startswith(("http://", "https://")):
        download_headers = info.get("http_headers", {})

        async def stream_direct():
            timeout = httpx.Timeout(10.0, connect=30.0, read=300.0)
            client = httpx.AsyncClient(timeout=timeout)
            try:
                async with client.stream("GET", video_url, headers=download_headers) as r:
                    r.raise_for_status()
                    async for chunk in r.aiter_bytes(chunk_size=65536):
                        yield chunk
            finally:
                await client.aclose()

        resp_headers = {"Content-Disposition": content_disposition, "Accept-Ranges": "bytes"}
        filesize = selected_format.get("filesize") or selected_format.get("filesize_approx")
        if filesize:
            resp_headers["Content-Length"] = str(filesize)

        return StreamingResponse(stream_direct(), media_type=get_mime_type(ext), headers=resp_headers)

    # ── Path B: HLS / DASH / other → pipe yt-dlp subprocess to response ───
    # Uses the same Python interpreter so the venv's yt-dlp is used.
    async def stream_via_ytdlp():
        proc = await asyncio.create_subprocess_exec(
            sys.executable, "-m", "yt_dlp",
            "--no-playlist", "--quiet",
            "-f", format_id,
            "-o", "-",      # write video bytes to stdout
            url,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.DEVNULL,
        )
        try:
            while True:
                chunk = await proc.stdout.read(65536)
                if not chunk:
                    break
                yield chunk
        finally:
            try:
                proc.terminate()
                await proc.wait()
            except Exception:
                pass

    return StreamingResponse(
        stream_via_ytdlp(),
        media_type=get_mime_type(ext),
        headers={"Content-Disposition": content_disposition},
    )


# ─── 3. GET /api/health ───────────────────────────────────────────────────────

@app.get("/api/health")
def health_check():
    return {
        "status": "healthy",
        "uptime_seconds": int(time.time() - startup_time),
        "version": "1.0.0",
    }
