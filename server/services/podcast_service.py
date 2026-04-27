"""播客搜索服务，使用 iTunes Podcast Search 作为公开索引源。"""

import asyncio
import logging

import httpx

logger = logging.getLogger(__name__)


class PodcastService:
    def __init__(self):
        self.search_url = "https://itunes.apple.com/search"
        self.enabled = True

    async def search(self, query: str, limit: int = 20) -> list[dict]:
        episode_limit = max(1, min(limit, 20) // 2)
        show_limit = max(1, min(limit, 20) - episode_limit)

        try:
            async with httpx.AsyncClient(timeout=15) as client:
                episode_resp, show_resp = await asyncio.gather(
                    client.get(
                        self.search_url,
                        params={
                            "term": query,
                            "entity": "podcastEpisode",
                            "media": "podcast",
                            "limit": episode_limit,
                            "country": "CN",
                        },
                    ),
                    client.get(
                        self.search_url,
                        params={
                            "term": query,
                            "entity": "podcast",
                            "media": "podcast",
                            "limit": show_limit,
                            "country": "CN",
                        },
                    ),
                )
                episode_resp.raise_for_status()
                show_resp.raise_for_status()

                episode_results = self._map_episode_results(
                    episode_resp.json().get("results", [])
                )
                show_results = self._map_show_results(show_resp.json().get("results", []))
                return (episode_results + show_results)[:limit]
        except Exception as exc:
            logger.warning("Podcast search failed: %s", exc)
            return []

    def _map_episode_results(self, items: list[dict]) -> list[dict]:
        results = []
        for item in items:
            track_id = item.get("trackId")
            if track_id is None:
                continue

            preview_url = str(item.get("previewUrl") or "").strip()
            episode_url = str(item.get("episodeUrl") or "").strip()
            track_view_url = str(item.get("trackViewUrl") or "").strip()
            series_name = str(item.get("collectionName") or item.get("trackName") or "").strip()
            author_name = str(item.get("artistName") or "").strip()

            results.append(
                {
                    "id": f"podcast-episode-{track_id}",
                    "title": str(item.get("trackName") or "Unknown Episode").strip(),
                    "source": "podcast",
                    "media_type": "audio",
                    "media_subtype": "podcast_episode",
                    "thumbnail_url": item.get("artworkUrl600", "")
                    or item.get("artworkUrl100", ""),
                    "duration_seconds": int((item.get("trackTimeMillis") or 0) / 1000),
                    "play_url": preview_url or episode_url or track_view_url,
                    "playback_kind": "native" if preview_url else "external_open",
                    "is_playable": bool(preview_url),
                    "availability": "preview" if preview_url else "indexed_only",
                    "source_tier": "official_api",
                    "canonical_url": episode_url or track_view_url or preview_url,
                    "artist_or_author": author_name,
                    "album_or_series": series_name,
                    "description": str(item.get("description") or "").strip(),
                    "highlights": [],
                    "ai_summary": None,
                }
            )

        return results

    def _map_show_results(self, items: list[dict]) -> list[dict]:
        results = []
        for item in items:
            collection_id = item.get("collectionId") or item.get("trackId")
            if collection_id is None:
                continue

            view_url = str(item.get("collectionViewUrl") or item.get("trackViewUrl") or "").strip()
            results.append(
                {
                    "id": f"podcast-show-{collection_id}",
                    "title": str(item.get("collectionName") or item.get("trackName") or "Unknown Show").strip(),
                    "source": "podcast",
                    "media_type": "audio",
                    "media_subtype": "podcast_show",
                    "thumbnail_url": item.get("artworkUrl600", "")
                    or item.get("artworkUrl100", ""),
                    "duration_seconds": 0,
                    "play_url": view_url,
                    "playback_kind": "external_open",
                    "is_playable": False,
                    "availability": "indexed_only",
                    "source_tier": "official_api",
                    "canonical_url": view_url,
                    "artist_or_author": str(item.get("artistName") or "").strip(),
                    "album_or_series": str(item.get("collectionName") or item.get("trackName") or "").strip(),
                    "description": str(item.get("primaryGenreName") or "Podcast").strip(),
                    "highlights": [],
                    "ai_summary": None,
                }
            )

        return results
