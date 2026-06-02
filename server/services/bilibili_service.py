"""Bilibili 搜索服务（公开 API，无需 Key）"""

import logging
import httpx

logger = logging.getLogger(__name__)


class BilibiliService:
    def __init__(self):
        self.search_url = "https://api.bilibili.com/x/web-interface/search/type"
        self.enabled = True  # Bilibili 搜索不强制 Key

    async def search(self, query: str, limit: int = 20) -> list[dict]:
        try:
            headers = {
                "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
                "Referer": "https://www.bilibili.com",
            }
            async with httpx.AsyncClient(timeout=15, headers=headers) as client:
                resp = await client.get(
                    self.search_url,
                    params={
                        "search_type": "video",
                        "keyword": query,
                        "page": 1,
                        "page_size": min(limit, 50),
                    },
                )
                resp.raise_for_status()
                data = resp.json()

                results = []
                items = data.get("data", {}).get("result", [])

                for item in items[:limit]:
                    bvid = item.get("bvid", "")
                    # 清理标题中的 HTML 高亮标签
                    title = (
                        item.get("title", "")
                        .replace('<em class="keyword">', "")
                        .replace("</em>", "")
                    )
                    # 封面可能缺 scheme
                    pic = item.get("pic", "")
                    if pic.startswith("//"):
                        pic = "https:" + pic

                    results.append(
                        {
                            "id": bvid,
                            "title": title,
                            "source": "bilibili",
                            "media_type": "video",
                            "media_subtype": "video",
                            "thumbnail_url": pic,
                            "duration_seconds": self._parse_duration(
                                item.get("duration", "0:0")
                            ),
                            "play_url": f"https://www.bilibili.com/video/{bvid}",
                            "playback_kind": "external_open",
                            "is_playable": True,
                            "availability": "available",
                            "source_tier": "public_api",
                            "canonical_url": f"https://www.bilibili.com/video/{bvid}",
                            "artist_or_author": item.get("author", ""),
                            "album_or_series": "",
                            "description": item.get("description", ""),
                            "highlights": [],
                            "ai_summary": None,
                        }
                    )

                return results
        except Exception as e:
            logger.warning(f"Bilibili search failed: {e}")
            return []

    @staticmethod
    def _parse_duration(duration_str: str) -> int:
        """解析 Bilibili 的时长格式 'MM:SS' 或 'HH:MM:SS'"""
        try:
            parts = str(duration_str).split(":")
            if len(parts) == 2:
                return int(parts[0]) * 60 + int(parts[1])
            elif len(parts) == 3:
                return int(parts[0]) * 3600 + int(parts[1]) * 60 + int(parts[2])
            return 0
        except (ValueError, TypeError):
            return 0
