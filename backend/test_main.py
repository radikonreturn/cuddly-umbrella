import os
import pytest
from fastapi.testclient import TestClient
from unittest.mock import patch, MagicMock

# Set environment variables for testing before importing the app
os.environ["DISABLE_UA_CHECK"] = "true"
os.environ["ALLOWED_ORIGINS"] = "http://localhost:3000"

from app.main import app

client = TestClient(app)

def test_health_check():
    response = client.get("/api/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "healthy"
    assert "uptime_seconds" in data
    assert data["version"] == "1.0.0"

@patch("app.main._extract_info_sync")
def test_extract_video_success(mock_extract):
    mock_extract.return_value = {
        "title": "Test Video",
        "thumbnail": "https://example.com/thumb.jpg",
        "duration": 120,
        "formats": [
            {
                "format_id": "18",
                "height": 360,
                "width": 640,
                "ext": "mp4",
                "vcodec": "h264",
                "acodec": "aac",
                "url": "https://example.com/video360.mp4",
                "filesize": 1024000
            },
            {
                "format_id": "22",
                "height": 720,
                "width": 1280,
                "ext": "mp4",
                "vcodec": "h264",
                "acodec": "aac",
                "url": "https://example.com/video720.mp4",
                "filesize_approx": 2048000
            }
        ]
    }
    
    response = client.post("/api/extract", json={"url": "https://youtube.com/watch?v=123"})
    assert response.status_code == 200
    data = response.json()
    assert data["title"] == "Test Video"
    assert data["thumbnail"] == "https://example.com/thumb.jpg"
    assert data["duration"] == 120
    assert len(data["formats"]) == 2
    
    # Check formats filtered correctly
    f1 = data["formats"][0]
    assert f1["format_id"] == "18"
    assert f1["quality"] == "360p"
    assert f1["ext"] == "mp4"
    assert f1["filesize_approx"] == 1024000
    
    f2 = data["formats"][1]
    assert f2["format_id"] == "22"
    assert f2["quality"] == "720p"
    assert f2["filesize_approx"] == 2048000

@patch("app.main._extract_info_sync")
def test_extract_video_invalid_url(mock_extract):
    response = client.post("/api/extract", json={"url": "invalid-url"})
    assert response.status_code == 400
    assert "Link geçersiz" in response.json()["detail"]

@patch("app.main._extract_info_sync")
@patch("httpx.AsyncClient.send")
def test_download_video_success(mock_send, mock_extract):
    # Mock yt-dlp response
    mock_extract.return_value = {
        "title": "Test Video",
        "formats": [
            {
                "format_id": "18",
                "height": 360,
                "width": 640,
                "ext": "mp4",
                "url": "https://example.com/video360.mp4",
                "filesize": 1000000
            }
        ]
    }
    
    # Mock httpx response stream
    mock_resp = MagicMock()
    mock_resp.status_code = 200
    
    async def mock_aiter_bytes(*args, **kwargs):
        yield b"chunk1"
        yield b"chunk2"
    mock_resp.aiter_bytes = mock_aiter_bytes
    
    async def mock_aclose(*args, **kwargs):
        pass
    mock_resp.aclose = mock_aclose
    
    mock_send.return_value = mock_resp
    
    # Test request
    response = client.get("/api/download?url=https://youtube.com/watch?v=123&format_id=18")
    assert response.status_code == 200
    assert response.headers["Content-Disposition"] == "attachment; filename*=UTF-8''Test%20Video.mp4"
    assert response.headers["Content-Length"] == "1000000"
    assert response.content == b"chunk1chunk2"

@patch("app.main.verify_mobile_user_agent")
def test_user_agent_verification_active(mock_verify):
    # Temporarily activate UA check by overriding env variable
    with patch.dict(os.environ, {"DISABLE_UA_CHECK": "false", "MOBILE_USER_AGENT": "CuddleUmbrellaMobile/1.0"}):
        # We test UA validation by sending invalid agent
        response = client.get("/api/download?url=https://youtube.com/watch?v=123&format_id=18", headers={"User-Agent": "InvalidAgent"})
        assert response.status_code == 403
