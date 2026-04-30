from enum import Enum

from pydantic import BaseModel, Field


class MediaType(str, Enum):
    video = "video"
    audio = "audio"


class MediaSubtype(str, Enum):
    video = "video"
    music_track = "music_track"
    podcast_show = "podcast_show"
    podcast_episode = "podcast_episode"


class PlaybackKind(str, Enum):
    native = "native"
    web_embed = "web_embed"
    external_open = "external_open"


class Availability(str, Enum):
    available = "available"
    preview = "preview"
    indexed_only = "indexed_only"


class SourceTier(str, Enum):
    official_api = "official_api"
    public_api = "public_api"
    web_supplement = "web_supplement"


class SearchIntent(str, Enum):
    video = "video"
    audio = "audio"
    podcast = "podcast"
    mixed = "mixed"


class TimedSegment(BaseModel):
    timestamp_seconds: float
    text: str


class SearchResultItem(BaseModel):
    id: str
    title: str
    source: str  # "youtube" / "bilibili" / "spotify"
    media_type: MediaType
    media_subtype: MediaSubtype = MediaSubtype.video
    thumbnail_url: str = ""
    duration_seconds: int = 0
    play_url: str = ""
    playback_kind: PlaybackKind = PlaybackKind.external_open
    is_playable: bool = True
    availability: Availability = Availability.available
    source_tier: SourceTier = SourceTier.public_api
    canonical_url: str = ""
    artist_or_author: str = ""
    album_or_series: str = ""
    description: str = ""
    highlights: list[TimedSegment] = Field(default_factory=list)
    ai_summary: str | None = None


class SearchRequest(BaseModel):
    query: str
    page: int = 1
    limit: int = 20
    enhance_with_llm: bool = True
    media_type_preference: SearchIntent | None = None
    enable_web_supplement: bool = False
    sources: list[str] | None = None  # None = 全部可用源


class SearchResponse(BaseModel):
    results: list[SearchResultItem]
    total: int
    query_rewritten: str | None = None
