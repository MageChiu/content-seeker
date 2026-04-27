"""iTunes Search API 音频搜索服务（公开 API，无需 Key）"""

import logging
import re

import httpx

logger = logging.getLogger(__name__)


class ItunesService:
    def __init__(self):
        self.search_url = "https://itunes.apple.com/search"
        self.enabled = True

    async def search(
        self,
        query: str,
        limit: int = 20,
        allow_broad_match: bool = False,
    ) -> list[dict]:
        if not allow_broad_match and not self._looks_like_audio_query(query):
            return []

        try:
            async with httpx.AsyncClient(timeout=15) as client:
                resp = await client.get(
                    self.search_url,
                    params={
                        "term": query,
                        "entity": "song",
                        "media": "music",
                        "limit": min(limit, 50),
                        "country": "CN",
                    },
                    headers={
                        "User-Agent": (
                            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                            "AppleWebKit/537.36 (KHTML, like Gecko) "
                            "Chrome/123.0.0.0 Safari/537.36"
                        )
                    },
                )
                resp.raise_for_status()
                data = resp.json()
                items = data.get("results", [])

                results = []
                for item in items[:limit]:
                    preview_url = item.get("previewUrl", "").strip()
                    track_id = item.get("trackId")
                    if not preview_url or track_id is None:
                        continue

                    track_name = item.get("trackName", "").strip()
                    artist_name = item.get("artistName", "").strip()
                    collection_name = item.get("collectionName", "").strip()
                    description_parts = [
                        part
                        for part in [artist_name, collection_name]
                        if isinstance(part, str) and part
                    ]

                    results.append(
                        {
                            "id": str(track_id),
                            "title": self._build_title(track_name, artist_name),
                            "source": "itunes",
                            "media_type": "audio",
                            "media_subtype": "music_track",
                            "thumbnail_url": item.get("artworkUrl100", ""),
                            "duration_seconds": 30,
                            "play_url": preview_url,
                            "playback_kind": "native",
                            "is_playable": True,
                            "availability": "preview",
                            "source_tier": "official_api",
                            "canonical_url": item.get("trackViewUrl", "") or preview_url,
                            "artist_or_author": artist_name,
                            "album_or_series": collection_name,
                            "description": " / ".join(description_parts),
                            "highlights": [],
                            "ai_summary": None,
                        }
                    )

                return results
        except Exception as e:
            logger.warning("iTunes search failed: %s", e)
            return []

    @staticmethod
    def _build_title(track_name: str, artist_name: str) -> str:
        if track_name and artist_name:
            return f"{track_name} - {artist_name}"
        return track_name or artist_name or "Unknown Track"

    @staticmethod
    def _looks_like_audio_query(query: str) -> bool:
        normalized = query.strip().lower()
        if not normalized:
            return False

        keywords = (
            "纯音乐",
            "音乐",
            "歌曲",
            "bgm",
            "伴奏",
            "钢琴",
            "吉他",
            "白噪音",
            "轻音乐",
            "专注",
            "睡眠",
            "lofi",
            "lo-fi",
            "song",
            "music",
            "album",
            "artist",
            "track",
            "instrumental",
            "playlist",
        )
        if any(keyword in normalized for keyword in keywords):
            return True

        return bool(re.search(r"\b(mp3|audio)\b", normalized))
