"""Google 补充搜索与媒体结果过滤。"""

import logging
import os
from urllib.parse import urlparse

import httpx

logger = logging.getLogger(__name__)

SUPPORTED_DOMAINS = {
    "youtube.com": ("/watch", "/playlist", "/shorts"),
    "youtu.be": ("/",),
    "music.youtube.com": ("/watch",),
    "bilibili.com": ("/video/", "/list/", "/audio/"),
    "jamendo.com": ("/track/", "/album/", "/artist/"),
    "podcasts.apple.com": ("/podcast/",),
    "open.spotify.com": ("/track/", "/album/", "/episode/", "/show/"),
}
REJECT_URL_KEYWORDS = (
    "news",
    "forum",
    "bbs",
    "tieba",
    "download",
    "apk",
    "torrent",
    "ads",
    "ad/",
)
REJECT_TEXT_KEYWORDS = (
    "论坛",
    "新闻",
    "下载",
    "破解版",
    "搬运",
    "聚合",
    "广告",
)
MEDIA_TEXT_KEYWORDS = (
    "music",
    "song",
    "album",
    "audio",
    "video",
    "podcast",
    "episode",
    "playlist",
    "专辑",
    "歌曲",
    "音频",
    "视频",
    "播客",
    "节目",
    "单集",
    "播放",
)


class GoogleSearchService:
    def __init__(self):
        self.api_key = os.environ.get("GOOGLE_SEARCH_API_KEY", "")
        self.cx = os.environ.get("GOOGLE_SEARCH_CX", "")
        self.search_url = "https://customsearch.googleapis.com/customsearch/v1"
        self.enabled = bool(self.api_key and self.cx)

    async def search(self, query: str, limit: int = 10) -> list[dict]:
        if not self.enabled:
            logger.info("Google supplement disabled: missing api key or cx")
            return []

        try:
            async with httpx.AsyncClient(timeout=15) as client:
                resp = await client.get(
                    self.search_url,
                    params={
                        "key": self.api_key,
                        "cx": self.cx,
                        "q": query,
                        "num": min(limit, 10),
                    },
                )
                resp.raise_for_status()
                items = resp.json().get("items", [])
                filtered_items = filter_google_items(items)
                return [map_google_item_to_result(item) for item in filtered_items[:limit]]
        except Exception as exc:
            logger.warning("Google supplement search failed: %s", exc)
            return []


def filter_google_items(items: list[dict]) -> list[dict]:
    filtered = []
    for item in items:
        if is_rejected_google_item(item):
            continue
        if not is_supported_media_item(item):
            continue
        filtered.append(item)
    return filtered


def is_supported_media_item(item: dict) -> bool:
    url = str(item.get("link") or "").strip()
    if not url:
        return False

    parsed = urlparse(url)
    host = parsed.netloc.lower()
    if host.startswith("www."):
        host = host[4:]
    path = parsed.path.lower()

    for domain, valid_paths in SUPPORTED_DOMAINS.items():
        if host == domain or host.endswith(f".{domain}"):
            return any(path.startswith(prefix) for prefix in valid_paths)

    title_and_snippet = " ".join(
        [str(item.get("title") or "").lower(), str(item.get("snippet") or "").lower()]
    )
    return any(keyword in title_and_snippet for keyword in MEDIA_TEXT_KEYWORDS)


def is_rejected_google_item(item: dict) -> bool:
    url = str(item.get("link") or "").strip().lower()
    text = " ".join(
        [str(item.get("title") or "").lower(), str(item.get("snippet") or "").lower()]
    )
    if any(keyword in url for keyword in REJECT_URL_KEYWORDS):
        return True
    return any(keyword in text for keyword in REJECT_TEXT_KEYWORDS)


def map_google_item_to_result(item: dict) -> dict:
    url = str(item.get("link") or "").strip()
    page_map = guess_media_shape(url, str(item.get("title") or ""), str(item.get("snippet") or ""))
    pagemap = item.get("pagemap", {}) if isinstance(item.get("pagemap"), dict) else {}
    thumbnail_url = _extract_thumbnail(pagemap)
    artist_or_author = _extract_artist_or_author(item, pagemap)
    album_or_series = _extract_series(item, pagemap)

    return {
        "id": f"google-{abs(hash(url))}",
        "title": str(item.get("title") or url),
        "source": "google",
        "media_type": page_map["media_type"],
        "media_subtype": page_map["media_subtype"],
        "thumbnail_url": thumbnail_url,
        "duration_seconds": 0,
        "play_url": url,
        "playback_kind": "external_open",
        "is_playable": False,
        "availability": "indexed_only",
        "source_tier": "web_supplement",
        "canonical_url": url,
        "artist_or_author": artist_or_author,
        "album_or_series": album_or_series,
        "description": str(item.get("snippet") or ""),
        "highlights": [],
        "ai_summary": None,
    }


def guess_media_shape(url: str, title: str, snippet: str) -> dict:
    host = urlparse(url).netloc.lower()
    if host.startswith("www."):
        host = host[4:]
    text = f"{title} {snippet}".lower()

    if "podcast" in host or any(word in text for word in ("podcast", "播客", "单集", "episode", "节目")):
        subtype = "podcast_episode" if any(word in text for word in ("episode", "单集")) else "podcast_show"
        return {"media_type": "audio", "media_subtype": subtype}

    if any(word in text for word in ("song", "music", "album", "歌曲", "专辑", "音乐")) or "jamendo" in host:
        return {"media_type": "audio", "media_subtype": "music_track"}

    return {"media_type": "video", "media_subtype": "video"}


def _extract_thumbnail(pagemap: dict) -> str:
    for key in ("cse_image", "cse_thumbnail"):
        values = pagemap.get(key)
        if isinstance(values, list) and values:
            src = values[0].get("src")
            if isinstance(src, str):
                return src
    return ""


def _extract_artist_or_author(item: dict, pagemap: dict) -> str:
    metatags = pagemap.get("metatags")
    if isinstance(metatags, list) and metatags:
        author = metatags[0].get("author") or metatags[0].get("og:site_name")
        if isinstance(author, str):
            return author
    return str(item.get("displayLink") or "")


def _extract_series(item: dict, pagemap: dict) -> str:
    metatags = pagemap.get("metatags")
    if isinstance(metatags, list) and metatags:
        series = metatags[0].get("og:site_name")
        if isinstance(series, str):
            return series
    return str(item.get("displayLink") or "")
