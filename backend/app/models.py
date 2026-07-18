from pydantic import BaseModel, Field
from typing import List, Optional

class ExtractRequest(BaseModel):
    url: str = Field(..., description="The URL of the video to extract info from")

class FormatInfo(BaseModel):
    format_id: str = Field(..., description="Unique identifier for the video format")
    quality: str = Field(..., description="Resolution quality label (e.g. 360p, 720p, 1080p)")
    ext: str = Field(..., description="File extension of the video format")
    filesize_approx: Optional[int] = Field(None, description="Approximate file size in bytes")
    has_audio: bool = Field(..., description="True if the format contains audio")
    has_video: bool = Field(..., description="True if the format contains video")

class ExtractResponse(BaseModel):
    title: str = Field(..., description="Title of the video")
    thumbnail: Optional[str] = Field(None, description="URL of the video thumbnail")
    duration: Optional[int] = Field(None, description="Duration of the video in seconds")
    formats: List[FormatInfo] = Field(..., description="List of filtered progressive formats")
