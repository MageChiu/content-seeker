import asyncio

from services.itunes_service import ItunesService


class _FakeResponse:
    def __init__(self, payload: dict):
        self._payload = payload

    def raise_for_status(self) -> None:
        return None

    def json(self) -> dict:
        return self._payload


class _FakeAsyncClient:
    def __init__(self, *args, **kwargs):
        self.calls = []

    async def __aenter__(self):
        return self

    async def __aexit__(self, exc_type, exc, tb):
        return False

    async def get(self, url: str, params: dict, headers: dict):
        self.calls.append((url, params, headers))
        return _FakeResponse(
            {
                "results": [
                    {
                        "trackId": 1,
                        "trackName": "My Heart Will Go On",
                        "artistName": "Celine Dion",
                        "collectionName": "Let's Talk About Love",
                        "previewUrl": "https://audio.example.com/track.m4a",
                        "trackViewUrl": "https://music.example.com/track",
                        "artworkUrl100": "https://img.example.com/track.jpg",
                    }
                ]
            }
        )


def test_itunes_service_skips_plain_song_query_without_audio_hint(monkeypatch):
    client = _FakeAsyncClient()
    monkeypatch.setattr("services.itunes_service.httpx.AsyncClient", lambda *args, **kwargs: client)

    results = asyncio.run(ItunesService().search("My Heart Will Go On", limit=5))

    assert results == []
    assert client.calls == []


def test_itunes_service_allows_plain_song_query_when_broad_match_enabled(monkeypatch):
    client = _FakeAsyncClient()
    monkeypatch.setattr("services.itunes_service.httpx.AsyncClient", lambda *args, **kwargs: client)

    results = asyncio.run(
        ItunesService().search(
            "My Heart Will Go On",
            limit=5,
            allow_broad_match=True,
        )
    )

    assert len(results) == 1
    assert results[0]["source"] == "itunes"
    assert results[0]["media_type"] == "audio"
    assert results[0]["artist_or_author"] == "Celine Dion"
    assert client.calls[0][1]["term"] == "My Heart Will Go On"
