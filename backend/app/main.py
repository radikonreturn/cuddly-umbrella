import os
import re
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

# Load environment variables
load_dotenv()

# Initialize Rate Limiter (IP-based)
limiter = Limiter(key_func=get_remote_address)

app = FastAPI(
    title="Video Extraction Backend",
    description="Backend API for extracting and proxy-streaming video formats using yt-dlp.",
    version="1.0.0"
)

# Attach rate limiter to app state and register exception handler
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# Record startup time for health/uptime check
startup_time = time.time()

# CORS Config - Close wide-open access by default. Allow only specified origins from env.
allowed_origins = [org.strip() for org in os.getenv("ALLOWED_ORIGINS", "").split(",") if org.strip()]
if not allowed_origins:
    # Fallback to local origin for development, avoiding wildcards ("*")
    allowed_origins = ["http://localhost:3000"]

app.add_middleware(
    CORSMiddleware,
    allow_origins=allowed_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# User-Agent Verification Dependency for Mobile App Client
async def verify_mobile_user_agent(user_agent: Optional[str] = Header(None)):
    """
    Enforces access control by verifying that the request originates from the mobile app client.
    Can be bypassed in local development using the DISABLE_UA_CHECK environment variable.
    """
    if os.getenv("DISABLE_UA_CHECK", "false").lower() == "true":
        return user_agent
        
    allowed_ua = os.getenv("MOBILE_USER_AGENT", "CuddleUmbrellaMobile/1.0")
    if not user_agent:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Access forbidden: Missing User-Agent header"
        )
    
    # Allow exact match, or prefix matching (e.g. CuddleUmbrellaMobile/1.0.1)
    ua_base = allowed_ua.split("/")[0] + "/"
    if user_agent != allowed_ua and not user_agent.startswith(ua_base):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Access forbidden: Invalid User-Agent"
        )
    return user_agent

# Helper to sanitize and encode filenames for Content-Disposition header
def sanitize_filename(title: str) -> str:
    # Remove chars that are illegal in file names
    clean_title = re.sub(r'[\\/*?:"<>|]', "", title)
    return clean_title.strip()

def get_mime_type(ext: str) -> str:
    mime_types = {
        "mp4": "video/mp4",
        "webm": "video/webm",
        "mkv": "video/x-matroska",
        "3gp": "video/3gpp",
        "flv": "video/x-flv",
        "avi": "video/x-msvideo",
        "mov": "video/quicktime",
        "ts": "video/MP2T",
    }
    return mime_types.get(ext.lower(), "application/octet-stream")

def validate_video_url(url: str):
    if not url or not url.startswith(("http://", "https://")):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Link geçersiz. URL http:// veya https:// ile başlamalıdır."
        )

# Target synchronous extraction function to be executed in thread pool
def _extract_info_sync(url: str) -> dict:
    ydl_opts = {
        'noplaylist': True,
        'quiet': True,
        'no_warnings': True,
        # Avoid downloading video, just extract information
        'extract_flat': False,
    }
    with yt_dlp.YoutubeDL(ydl_opts) as ydl:
        return ydl.extract_info(url, download=False)

# 1. POST /api/extract
@app.post("/api/extract", response_model=ExtractResponse)
@limiter.limit("10/minute")
async def extract_video(
    request: Request,
    body: ExtractRequest,
    user_agent: str = Depends(verify_mobile_user_agent)
):
    validate_video_url(body.url)
    
    try:
        # Run blocking yt-dlp extraction in an external thread pool to prevent blocking event loop
        info = await to_thread.run_sync(_extract_info_sync, body.url)
    except yt_dlp.utils.UnsupportedError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Bu platform desteklenmiyor veya link geçersiz."
        )
    except yt_dlp.utils.DownloadError as e:
        msg = str(e)
        if "Unsupported URL" in msg or "not a valid URL" in msg:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Bu platform desteklenmiyor veya link geçersiz."
            )
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Link geçersiz veya video çekilemedi."
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Video bilgisi alınamadı: {str(e)}"
        )

    if not info:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Video bilgileri çözümlenemedi."
        )
        
    if 'entries' in info:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Oynatma listeleri desteklenmiyor. Lütfen tek bir video linki girin."
        )

    raw_formats = info.get('formats', [])
    formats_list = []

    if not raw_formats:
        # Fallback: if no format list is returned but a direct url is present
        video_url = info.get('url')
        if video_url:
            height = info.get('height')
            width = info.get('width')
            res = min(height, width) if (height and width) else (height or width or 360)
            formats_list.append(
                FormatInfo(
                    format_id=info.get("format_id") or "default",
                    quality=f"{res}p",
                    ext=info.get("ext") or "mp4",
                    filesize_approx=info.get("filesize") or info.get("filesize_approx"),
                    has_audio=True,
                    has_video=True
                )
            )
    else:
        for fmt in raw_formats:
            vcodec = fmt.get('vcodec')
            acodec = fmt.get('acodec')
            has_video = vcodec is not None and vcodec != 'none'
            has_audio = acodec is not None and acodec != 'none'

            # Filter progressive formats (contains both video and audio)
            if not (has_video and has_audio):
                continue

            height = fmt.get('height')
            width = fmt.get('width')

            res = None
            if height and width:
                res = min(height, width)
            elif height:
                res = height
            elif width:
                res = width

            # Filter for standard resolutions
            if res not in [360, 720, 1080]:
                continue

            formats_list.append(
                FormatInfo(
                    format_id=fmt.get("format_id"),
                    quality=f"{res}p",
                    ext=fmt.get("ext"),
                    filesize_approx=fmt.get("filesize") or fmt.get("filesize_approx"),
                    has_audio=True,
                    has_video=True
                )
            )

    # Resolve thumbnail
    thumbnail = info.get('thumbnail')
    if not thumbnail and info.get('thumbnails'):
        thumbnail = info['thumbnails'][-1].get('url')

    return ExtractResponse(
        title=info.get('title', 'Unknown Title'),
        thumbnail=thumbnail,
        duration=info.get('duration'),
        formats=formats_list
    )

# 2. GET /api/download
@app.get("/api/download")
@limiter.limit("10/minute")
async def download_video(
    request: Request,
    url: str = Query(..., description="The URL of the video"),
    format_id: str = Query(..., description="The selected format ID to download"),
    user_agent: Optional[str] = Depends(verify_mobile_user_agent)
):
    validate_video_url(url)

    try:
        # Fetch fresh info to resolve format URL and headers
        info = await to_thread.run_sync(_extract_info_sync, url)
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Video bilgisi alınamadı: {str(e)}"
        )

    if not info:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Video bilgileri çözümlenemedi."
        )

    # Find the requested format
    selected_format = None
    for fmt in info.get('formats', []):
        if fmt.get('format_id') == format_id:
            selected_format = fmt
            break

    # If no formats list but single url matches
    if not selected_format and info.get('format_id') == format_id:
        selected_format = info

    if not selected_format:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Seçilen format bulunamadı veya geçersiz format ID."
        )

    video_url = selected_format.get('url')
    if not video_url:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Format için indirme URL'i çözümlenemedi."
        )

    # Set up client headers provided by yt-dlp to access the resource successfully
    download_headers = info.get('http_headers', {})
    
    # Build clean filename
    title = info.get('title', 'video')
    ext = selected_format.get('ext', 'mp4')
    filename = f"{sanitize_filename(title)}.{ext}"
    
    # URL encode filename for RFC 6266 compliance
    encoded_filename = urllib.parse.quote(filename)
    content_disposition = f"attachment; filename*=UTF-8''{encoded_filename}"

    # Open connection and verify status code before streaming
    timeout = httpx.Timeout(10.0, connect=30.0, read=300.0)
    client = httpx.AsyncClient(timeout=timeout)
    try:
        req = client.build_request("GET", video_url, headers=download_headers)
        resp = await client.send(req, stream=True)
        if resp.status_code >= 400:
            await resp.aclose()
            await client.aclose()
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Kaynak video sunucusu hata döndürdü: {resp.status_code}"
            )
    except Exception as e:
        await client.aclose()
        if isinstance(e, HTTPException):
            raise e
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Video akışı başlatılamadı: {str(e)}"
        )

    async def stream_generator():
        try:
            async for chunk in resp.aiter_bytes(chunk_size=65536):
                yield chunk
        finally:
            await resp.aclose()
            await client.aclose()

    response_headers = {
        "Content-Disposition": content_disposition,
        "Accept-Ranges": "bytes"
    }

    # Set Content-Length if available in the format info
    filesize = selected_format.get('filesize') or selected_format.get('filesize_approx')
    if filesize:
        response_headers["Content-Length"] = str(filesize)

    return StreamingResponse(
        stream_generator(),
        media_type=get_mime_type(ext),
        headers=response_headers
    )

# 3. GET /api/health
@app.get("/api/health")
def health_check():
    """
    Simple health check endpoint for Render.com/Fly.io uptime monitoring.
    This endpoint is exempt from User-Agent checks.
    """
    return {
        "status": "healthy",
        "uptime_seconds": int(time.time() - startup_time),
        "version": "1.0.0"
    }
