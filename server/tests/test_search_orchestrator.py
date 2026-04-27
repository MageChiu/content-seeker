from models.schemas import SearchIntent
from services.search_orchestrator import (
    build_dedupe_key,
    detect_search_intent,
    select_sources,
    sort_and_deduplicate_results,
)


def test_detect_search_intent_prefers_podcast_keywords():
    intent = detect_search_intent("科技播客 第 12 期 episode")

    assert intent == SearchIntent.podcast


def test_select_sources_adds_google_only_when_enabled():
    sources = select_sources(
        SearchIntent.audio,
        requested_sources=None,
        enable_web_supplement=True,
    )

    assert sources == ["itunes", "jamendo", "youtube", "google"]


def test_sort_and_deduplicate_results_prefers_playable_official_sources():
    duplicate_google = {
        "id": "google-1",
        "title": "Focus Music",
        "source": "google",
        "media_type": "audio",
        "media_subtype": "music_track",
        "duration_seconds": 180,
        "play_url": "https://jamendo.com/track/1?utm_source=test",
        "canonical_url": "https://jamendo.com/track/1?utm_source=test",
        "playback_kind": "external_open",
        "is_playable": False,
        "availability": "indexed_only",
        "source_tier": "web_supplement",
        "artist_or_author": "Artist",
        "album_or_series": "Album",
    }
    official_jamendo = {
        "id": "jamendo-1",
        "title": "Focus Music",
        "source": "jamendo",
        "media_type": "audio",
        "media_subtype": "music_track",
        "duration_seconds": 182,
        "play_url": "https://stream.jamendo.com/track/1.mp3",
        "canonical_url": "https://jamendo.com/track/1",
        "playback_kind": "native",
        "is_playable": True,
        "availability": "available",
        "source_tier": "official_api",
        "artist_or_author": "Artist",
        "album_or_series": "Album",
    }

    results = sort_and_deduplicate_results(
        [duplicate_google, official_jamendo],
        SearchIntent.audio,
    )

    assert len(results) == 1
    assert results[0]["source"] == "jamendo"
    assert build_dedupe_key(duplicate_google) == build_dedupe_key(official_jamendo)
