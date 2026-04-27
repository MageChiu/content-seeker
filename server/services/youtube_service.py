"""YouTube Data API v3 搜索服务"""

import os
import re
import logging
import httpx

logger = logging.getLogger(__name__)


def _parse_iso8601_duration(duration: str) -> int:
    """将 ISO 8601 时长 (PT1H2M3S) 转为秒数"""
    match = re.match(r"PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?", duration)
    if not match:
        return 0
    h, m, s = (int(x) if x else 0 for x in match.groups())
    return h * 3600 + m * 60 + s


class YouTubeService:
    def __init__(self):
        self.api_key = os.environ.get("YOUTUBE_API_KEY", "")
        self.base_url = "https://www.googleapis.com/youtube/v3"
        self.enabled = bool(self.api_key)

    async def search(self, query: str, limit: int = 20) -> list[dict]:
        if not self.enabled:
            logger.info("YouTube service disabled: no API key")
            return []

        async with httpx.AsyncClient(timeout=15) as client:
            # Step 1: 搜索
            resp = await client.get(
                f"{self.base_url}/search",
                params={
                    "part": "snippet",
                    "q": query,
                    "type": "video",
                    "maxResults": min(limit, 50),
                    "key": self.api_key,
                },
            )
            resp.raise_for_status()
            data = resp.json()

            results = []
            video_ids = []

            for item in data.get("items", []):
                vid = item["id"]["videoId"]
                video_ids.append(vid)
                snippet = item["snippet"]
                results.append(
                    {
                        "id": vid,
                        "title": snippet["title"],
                        "source": "youtube",
                        "media_type": "video",
                        "media_subtype": "video",
                        "thumbnail_url": snippet.get("thumbnails", {})
                        .get("high", {})
                        .get("url", ""),
                        "duration_seconds": 0,
                        "play_url": f"https://www.youtube.com/watch?v={vid}",
                        "playback_kind": "external_open",
                        "is_playable": True,
                        "availability": "available",
                        "source_tier": "official_api",
                        "canonical_url": f"https://www.youtube.com/watch?v={vid}",
                        "artist_or_author": snippet.get("channelTitle", ""),
                        "album_or_series": "",
                        "description": snippet.get("description", ""),
                        "highlights": [],
                        "ai_summary": None,
                    }
                )

            # Step 2: 批量获取时长
            if video_ids:
                detail_resp = await client.get(
                    f"{self.base_url}/videos",
                    params={
                        "part": "contentDetails",
                        "id": ",".join(video_ids),
                        "key": self.api_key,
                    },
                )
                if detail_resp.status_code == 200:
                    details = detail_resp.json()
                    duration_map = {
                        d["id"]: _parse_iso8601_duration(
                            d["contentDetails"]["duration"]
                        )
                        for d in details.get("items", [])
                    }
                    for r in results:
                        r["duration_seconds"] = duration_map.get(r["id"], 0)

            return results
