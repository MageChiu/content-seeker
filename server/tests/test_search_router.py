from fastapi.testclient import TestClient

from main import app
from routers import search as search_router


class _FakeLLMService:
    async def rewrite_query(self, query: str) -> str:
        return query

    async def rerank_and_summarize(self, original_query: str, results: list[dict]) -> list[dict]:
        return results


class _RecordingService:
    def __init__(self, name: str, payload: list[dict], calls: list):
        self.name = name
        self.payload = payload
        self.calls = calls

    async def search(self, query: str, limit: int = 20, **kwargs) -> list[dict]:
        self.calls.append((self.name, kwargs))
        return self.payload


def test_search_endpoint_routes_podcast_query_and_returns_unified_fields(monkeypatch):
    calls: list[str] = []

    monkeypatch.setattr(search_router, "LLMService", lambda: _FakeLLMService())
    monkeypatch.setattr(
        search_router,
        "PodcastService",
        lambda: _RecordingService(
            "podcast",
            [
                {
                    "id": "podcast-episode-1",
                    "title": "科技播客第 1 期",
                    "source": "podcast",
                    "media_type": "audio",
                    "media_subtype": "podcast_episode",
                    "thumbnail_url": "https://img.example.com/podcast.jpg",
                    "duration_seconds": 1800,
                    "play_url": "https://audio.example.com/episode-1.mp3",
                    "playback_kind": "native",
                    "is_playable": True,
                    "availability": "available",
                    "source_tier": "official_api",
                    "canonical_url": "https://podcast.example.com/episodes/1",
                    "artist_or_author": "科技时间",
                    "album_or_series": "科技时间",
                    "description": "本期聊统一搜索",
                    "highlights": [],
                    "ai_summary": None,
                }
            ],
            calls,
        ),
    )
    monkeypatch.setattr(
        search_router,
        "ItunesService",
        lambda: _RecordingService("itunes", [], calls),
    )
    monkeypatch.setattr(
        search_router,
        "YouTubeService",
        lambda: _RecordingService("youtube", [], calls),
    )
    monkeypatch.setattr(
        search_router,
        "BilibiliService",
        lambda: _RecordingService("bilibili", [], calls),
    )
    monkeypatch.setattr(
        search_router,
        "JamendoService",
        lambda: _RecordingService("jamendo", [], calls),
    )
    monkeypatch.setattr(
        search_router,
        "GoogleSearchService",
        lambda: _RecordingService("google", [], calls),
    )

    client = TestClient(app)
    response = client.post(
        "/api/v1/search",
        json={
            "query": "科技播客 episode",
            "enhance_with_llm": False,
            "enable_web_supplement": True,
        },
    )

    data = response.json()

    assert response.status_code == 200
    assert [name for name, _ in calls] == ["podcast", "itunes", "youtube", "google"]
    assert data["total"] == 1
    assert data["results"][0]["media_subtype"] == "podcast_episode"
    assert data["results"][0]["playback_kind"] == "native"
    assert data["results"][0]["artist_or_author"] == "科技时间"


def test_search_endpoint_allows_broad_itunes_match_for_audio_intent(monkeypatch):
    calls: list[tuple[str, dict]] = []

    monkeypatch.setattr(search_router, "LLMService", lambda: _FakeLLMService())
    monkeypatch.setattr(
        search_router,
        "ItunesService",
        lambda: _RecordingService(
            "itunes",
            [
                {
                    "id": "track-1",
                    "title": "Some Song - Artist",
                    "source": "itunes",
                    "media_type": "audio",
                    "media_subtype": "music_track",
                    "thumbnail_url": "",
                    "duration_seconds": 30,
                    "play_url": "https://audio.example.com/track-1.m4a",
                    "playback_kind": "native",
                    "is_playable": True,
                    "availability": "preview",
                    "source_tier": "official_api",
                    "canonical_url": "https://music.example.com/track-1",
                    "artist_or_author": "Artist",
                    "album_or_series": "Album",
                    "description": "",
                    "highlights": [],
                    "ai_summary": None,
                }
            ],
            calls,
        ),
    )
    monkeypatch.setattr(
        search_router,
        "YouTubeService",
        lambda: _RecordingService("youtube", [], calls),
    )
    monkeypatch.setattr(
        search_router,
        "BilibiliService",
        lambda: _RecordingService("bilibili", [], calls),
    )
    monkeypatch.setattr(
        search_router,
        "JamendoService",
        lambda: _RecordingService("jamendo", [], calls),
    )
    monkeypatch.setattr(
        search_router,
        "PodcastService",
        lambda: _RecordingService("podcast", [], calls),
    )
    monkeypatch.setattr(
        search_router,
        "GoogleSearchService",
        lambda: _RecordingService("google", [], calls),
    )

    client = TestClient(app)
    response = client.post(
        "/api/v1/search",
        json={
            "query": "My Heart Will Go On",
            "enhance_with_llm": False,
            "media_type_preference": "audio",
            "sources": ["itunes"],
        },
    )

    assert response.status_code == 200
    assert calls == [("itunes", {"allow_broad_match": True})]
    assert response.json()["total"] == 1
