"""统一多媒体搜索编排辅助逻辑。"""

import re
from typing import Iterable
from urllib.parse import parse_qsl, urlencode, urlparse, urlunparse

from models.schemas import SearchIntent

SOURCE_TIERS = {
    "youtube": "official_api",
    "itunes": "official_api",
    "jamendo": "official_api",
    "podcast": "official_api",
    "bilibili": "public_api",
    "google": "web_supplement",
}

_VIDEO_KEYWORDS = (
    "视频",
    "教程",
    "讲解",
    "演示",
    "直播",
    "mv",
    "movie",
    "video",
    "lesson",
    "course",
    "review",
    "trailer",
)
_AUDIO_KEYWORDS = (
    "纯音乐",
    "音乐",
    "歌曲",
    "bgm",
    "伴奏",
    "白噪音",
    "钢琴",
    "吉他",
    "睡眠",
    "lofi",
    "lo-fi",
    "album",
    "track",
    "song",
    "music",
    "instrumental",
)
_PODCAST_KEYWORDS = (
    "播客",
    "podcast",
    "节目",
    "单集",
    "ep",
    "episode",
    "访谈",
    "talk show",
)

_TIER_WEIGHT = {
    "official_api": 30,
    "public_api": 20,
    "web_supplement": 10,
}
_PLAYBACK_WEIGHT = {
    "native": 15,
    "web_embed": 8,
    "external_open": 4,
}
_SUBTYPE_INTENT_BONUS = {
    SearchIntent.video: {"video": 12},
    SearchIntent.audio: {"music_track": 12, "podcast_episode": 2, "podcast_show": 1},
    SearchIntent.podcast: {"podcast_episode": 12, "podcast_show": 10, "music_track": -4},
    SearchIntent.mixed: {},
}


def detect_search_intent(
    query: str, preferred: SearchIntent | None = None
) -> SearchIntent:
    if preferred is not None:
        return preferred

    normalized = query.strip().lower()
    if not normalized:
        return SearchIntent.mixed

    video_hits = _count_keyword_hits(normalized, _VIDEO_KEYWORDS)
    audio_hits = _count_keyword_hits(normalized, _AUDIO_KEYWORDS)
    podcast_hits = _count_keyword_hits(normalized, _PODCAST_KEYWORDS)

    if podcast_hits > max(video_hits, audio_hits):
        return SearchIntent.podcast
    if audio_hits > max(video_hits, podcast_hits):
        return SearchIntent.audio
    if video_hits > max(audio_hits, podcast_hits):
        return SearchIntent.video
    return SearchIntent.mixed


def select_sources(
    intent: SearchIntent,
    requested_sources: list[str] | None = None,
    enable_web_supplement: bool = False,
) -> list[str]:
    if intent == SearchIntent.video:
        candidates = ["youtube", "bilibili"]
    elif intent == SearchIntent.audio:
        candidates = ["itunes", "jamendo", "youtube"]
    elif intent == SearchIntent.podcast:
        candidates = ["podcast", "itunes", "youtube"]
    else:
        candidates = ["youtube", "bilibili", "itunes", "jamendo", "podcast"]

    if enable_web_supplement:
        candidates.append("google")

    if requested_sources:
        requested = set(requested_sources)
        candidates = [source for source in candidates if source in requested]

    return _dedupe_preserve_order(candidates)


def sort_and_deduplicate_results(
    results: Iterable[dict], intent: SearchIntent
) -> list[dict]:
    ranked = sorted(results, key=lambda item: score_result(item, intent), reverse=True)
    deduped: list[dict] = []
    seen_keys: set[str] = set()

    for item in ranked:
        dedupe_key = build_dedupe_key(item)
        if dedupe_key in seen_keys:
            continue
        seen_keys.add(dedupe_key)
        deduped.append(item)

    return deduped


def score_result(result: dict, intent: SearchIntent) -> int:
    source_tier = str(result.get("source_tier") or SOURCE_TIERS.get(result.get("source"), "public_api"))
    playback_kind = str(result.get("playback_kind") or "external_open")
    subtype = str(result.get("media_subtype") or "")
    title = str(result.get("title") or "").lower()
    description = str(result.get("description") or "").lower()

    score = 0
    score += _TIER_WEIGHT.get(source_tier, 0)
    score += _PLAYBACK_WEIGHT.get(playback_kind, 0)
    if result.get("is_playable"):
        score += 10
    if result.get("availability") == "preview":
        score += 2

    score += _SUBTYPE_INTENT_BONUS.get(intent, {}).get(subtype, 0)

    if intent == SearchIntent.video and any(word in title or word in description for word in ("tutorial", "教程", "讲解")):
        score += 2
    if intent == SearchIntent.audio and any(word in title or word in description for word in ("music", "音乐", "纯音乐", "bgm")):
        score += 2
    if intent == SearchIntent.podcast and any(word in title or word in description for word in ("podcast", "播客", "episode", "单集", "节目")):
        score += 2

    duration_seconds = int(result.get("duration_seconds") or 0)
    if 30 <= duration_seconds <= 5400:
        score += 1

    return score


def build_dedupe_key(result: dict) -> str:
    canonical_url = normalize_url(str(result.get("canonical_url") or result.get("play_url") or ""))
    if canonical_url:
        return canonical_url

    normalized_title = _normalize_text(result.get("title", ""))
    normalized_artist = _normalize_text(result.get("artist_or_author", ""))
    normalized_series = _normalize_text(result.get("album_or_series", ""))
    duration_bucket = int(int(result.get("duration_seconds") or 0) / 5)
    return "|".join(
        [
            str(result.get("media_type") or ""),
            str(result.get("media_subtype") or ""),
            normalized_title,
            normalized_artist,
            normalized_series,
            str(duration_bucket),
        ]
    )


def normalize_url(url: str) -> str:
    if not url:
        return ""

    parsed = urlparse(url.strip())
    if not parsed.netloc:
        return url.strip()

    query_pairs = parse_qsl(parsed.query, keep_blank_values=False)
    filtered_query = [(key, value) for key, value in query_pairs if not key.startswith("utm_")]
    normalized_netloc = parsed.netloc.lower()
    if normalized_netloc.startswith("www."):
        normalized_netloc = normalized_netloc[4:]

    return urlunparse(
        (
            parsed.scheme.lower() or "https",
            normalized_netloc,
            parsed.path.rstrip("/") or parsed.path,
            "",
            urlencode(filtered_query),
            "",
        )
    )


def _count_keyword_hits(text: str, keywords: tuple[str, ...]) -> int:
    return sum(1 for keyword in keywords if keyword in text)


def _dedupe_preserve_order(items: list[str]) -> list[str]:
    seen: set[str] = set()
    output: list[str] = []
    for item in items:
        if item in seen:
            continue
        seen.add(item)
        output.append(item)
    return output


def _normalize_text(value: str) -> str:
    text = re.sub(r"\s+", " ", str(value).strip().lower())
    return re.sub(r"[^a-z0-9\u4e00-\u9fff ]+", "", text)
