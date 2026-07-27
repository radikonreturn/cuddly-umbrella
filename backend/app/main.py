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
    allowed_origins = ["*"]


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
    is_youtube = "youtube.com" in url or "youtu.be" in url
    opts = {
        "noplaylist": True,
        "quiet": True,
        "no_warnings": True,
        "extract_flat": False,
        "http_headers": {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
            "Accept-Language": "en-US,en;q=0.9",
        },
        # Suppress JS runtime warning – android_vr client works without it
        "extractor_args": {"youtube": {"player_client": ["android_vr", "web"]}},
    }
    if is_youtube:
        opts["skip_download"] = True
        opts["check_formats"] = False

    with yt_dlp.YoutubeDL(opts) as ydl:
        return ydl.extract_info(url, download=False)


def _build_formats(raw_formats: list, info: dict) -> list:
    """
    Build the list of FormatInfo to return to the client.

    Strategy (four passes, stop at first non-empty result):
      1. Progressive direct-HTTP: both video+audio in one stream, proxyable
      2. Any single-stream video+audio (e.g. HLS for X/Twitter)
      3. DASH merge: pair best video-only + best audio-only per resolution
      4. Top-level yt-dlp selected URL fallback
    """
    def _parse_progressive(fmts, require_direct_http: bool) -> list:
        best: dict[str, FormatInfo] = {}
        for fmt in fmts:
            vcodec = fmt.get("vcodec")
            acodec = fmt.get("acodec")
            has_video = vcodec != "none"
            has_audio = acodec != "none"
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

    def _parse_dash_merge(fmts) -> list:
        """Build merged video+audio pairs from DASH/separate streams."""
        # Collect best audio-only format (prefer m4a/mp4a for broadest compatibility)
        audio_formats = [
            f for f in fmts
            if f.get("acodec") not in (None, "none")
            and f.get("vcodec") in (None, "none")
            and _is_direct_http(f)
        ]
        if not audio_formats:
            return []

        # Pick the best audio: prefer mp4a (m4a) at ~128k
        def audio_score(f):
            abr = f.get("abr") or 0
            codec = f.get("acodec") or ""
            prefer_mp4a = 1 if "mp4a" in codec else 0
            return (prefer_mp4a, abr)

        best_audio = max(audio_formats, key=audio_score)
        best_audio_id = best_audio.get("format_id")
        best_audio_size = best_audio.get("filesize") or best_audio.get("filesize_approx") or 0

        # Collect video-only formats
        video_formats = [
            f for f in fmts
            if f.get("vcodec") not in (None, "none")
            and f.get("acodec") in (None, "none")
            and _is_direct_http(f)
        ]
        if not video_formats:
            return []

        # Best video-only per resolution – prefer avc1 (H.264) for device compatibility
        best_per_res: dict[str, dict] = {}
        for f in video_formats:
            h = f.get("height")
            w = f.get("width")
            res = min(h, w) if (h and w) else (h or w)
            if not res:
                continue
            quality = f"{res}p"
            vcodec = f.get("vcodec") or ""
            existing = best_per_res.get(quality)
            if not existing:
                best_per_res[quality] = f
            else:
                # Prefer H.264 (avc1) > others; then by bitrate
                cur_is_avc = "avc" in (existing.get("vcodec") or "")
                new_is_avc = "avc" in vcodec
                cur_tbr = existing.get("tbr") or 0
                new_tbr = f.get("tbr") or 0
                if (not cur_is_avc and new_is_avc) or (cur_is_avc == new_is_avc and new_tbr > cur_tbr):
                    best_per_res[quality] = f

        result = []
        for quality, vfmt in best_per_res.items():
            vid_id = vfmt.get("format_id")
            vid_size = vfmt.get("filesize") or vfmt.get("filesize_approx") or 0
            combined_size = (vid_size + best_audio_size) or None
            ext = vfmt.get("ext") or "mp4"
            # Merged format uses '+' separator understood by yt-dlp
            result.append(FormatInfo(
                format_id=f"{vid_id}+{best_audio_id}",
                quality=quality,
                ext="mp4",   # ffmpeg will mux to mp4
                filesize_approx=combined_size,
                has_audio=True,
                has_video=True,
            ))

        return sorted(result,
                      key=lambda f: int(f.quality[:-1]) if f.quality[:-1].isdigit() else 0,
                      reverse=True)

    # Pass 1 – direct-HTTP progressive (single file with both streams)
    prog_direct = _parse_progressive(raw_formats, require_direct_http=True)

    # Pass 2 – any single-stream with both codecs (HLS etc.)
    prog_other = _parse_progressive(raw_formats, require_direct_http=False)

    # Pass 3 – DASH merge (separate video + audio → merged via yt-dlp subprocess)
    dash_merged = _parse_dash_merge(raw_formats)

    # Combine formats from different passes, prioritizing progressive over DASH-merged formats.
    formats_by_quality = {}
    for f in dash_merged:
        formats_by_quality[f.quality] = f
    for f in prog_other:
        formats_by_quality[f.quality] = f
    for f in prog_direct:
        formats_by_quality[f.quality] = f

    result = sorted(
        formats_by_quality.values(),
        key=lambda f: int(f.quality[:-1]) if f.quality[:-1].isdigit() else 0,
        reverse=True
    )
    if result:
        return result

    # Pass 4 – top-level URL that yt-dlp selected as fallback
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

    format_id = format_id.replace(" ", "+")

    try:
        info = await to_thread.run_sync(_extract_info_sync, url)
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Video bilgisi alınamadı: {str(e)}")

    # Locate the selected format
    is_merged = False
    selected_format = None
    if "+" in format_id:
        parts = format_id.split("+")
        if len(parts) == 2:
            v_id, a_id = parts[0], parts[1]
            all_fmts = info.get("formats", [])
            v_fmt = next((f for f in all_fmts if f.get("format_id") == v_id), None)
            a_fmt = next((f for f in all_fmts if f.get("format_id") == a_id), None)
            if v_fmt and a_fmt:
                is_merged = True
                v_size = v_fmt.get("filesize") or v_fmt.get("filesize_approx") or 0
                a_size = a_fmt.get("filesize") or a_fmt.get("filesize_approx") or 0
                selected_format = {
                    "format_id": format_id,
                    "ext": "mp4",
                    "url": v_fmt.get("url", ""),
                    "protocol": "merged",
                    "filesize": (v_size + a_size) or None,
                }

    if not selected_format:
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
    if not is_merged and _is_direct_http(selected_format) and video_url.startswith(("http://", "https://")):
        raw_headers = info.get("http_headers", {})
        download_headers = {k: v for k, v in raw_headers.items() if k.lower() not in ("host", "content-length")}

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
        exact_filesize = selected_format.get("filesize")
        if exact_filesize:
            resp_headers["Content-Length"] = str(exact_filesize)

        return StreamingResponse(stream_direct(), media_type=get_mime_type(ext), headers=resp_headers)

    # ── Path B: HLS / DASH / other → pipe yt-dlp subprocess to response ───
    # Uses the same Python interpreter so the venv's yt-dlp is used.
    async def stream_via_ytdlp():
        proc = await asyncio.create_subprocess_exec(
            sys.executable, "-m", "yt_dlp",
            "--no-playlist", "--quiet",
            "--extractor-args", "youtube:player_client=android_vr,web",
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
