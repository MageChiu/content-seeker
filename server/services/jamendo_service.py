"""Jamendo 公开音乐搜索服务。"""

import logging
import os

import httpx

logger = logging.getLogger(__name__)


class JamendoService:
    def __init__(self):
        self.client_id = os.environ.get("JAMENDO_CLIENT_ID", "")
        self.search_url = "https://api.jamendo.com/v3.0/tracks"
        self.enabled = bool(self.client_id)

    async def search(self, query: str, limit: int = 20) -> list[dict]:
        if not self.enabled:
            logger.info("Jamendo service disabled: no client id")
            return []

        try:
            async with httpx.AsyncClient(timeout=15) as client:
                resp = await client.get(
                    self.search_url,
                    params={
                        "client_id": self.client_id,
                        "format": "json",
                        "limit": min(limit, 50),
                        "audioformat": "mp31",
                        "namesearch": query,
                    },
                )
                resp.raise_for_status()
                items = resp.json().get("results", [])

                results = []
                for item in items[:limit]:
                    track_id = item.get("id")
                    if track_id is None:
                        continue

                    audio_url = str(item.get("audio") or "").strip()
                    share_url = str(item.get("shareurl") or "").strip()
                    title = str(item.get("name") or "").strip() or "Unknown Track"
                    artist_name = str(item.get("artist_name") or "").strip()
                    album_name = str(item.get("album_name") or "").strip()

                    results.append(
                        {
                            "id": f"jamendo-{track_id}",
                            "title": f"{title} - {artist_name}" if artist_name else title,
                            "source": "jamendo",
                            "media_type": "audio",
                            "media_subtype": "music_track",
                            "thumbnail_url": item.get("image", ""),
                            "duration_seconds": int(item.get("duration") or 0),
                            "play_url": audio_url or share_url,
                            "playback_kind": "native" if audio_url else "external_open",
                            "is_playable": bool(audio_url),
                            "availability": "available" if audio_url else "indexed_only",
                            "source_tier": "official_api",
                            "canonical_url": share_url or audio_url,
                            "artist_or_author": artist_name,
                            "album_or_series": album_name,
                            "description": " / ".join(
                                part for part in [artist_name, album_name] if part
                            ),
                            "highlights": [],
                            "ai_summary": None,
                        }
                    )

                return results
        except Exception as exc:
            logger.warning("Jamendo search failed: %s", exc)
            return []
