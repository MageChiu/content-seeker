from services.google_search_service import filter_google_items, map_google_item_to_result


def test_filter_google_items_keeps_supported_media_pages():
    items = [
        {
            "title": "Focus Playlist - Jamendo",
            "link": "https://www.jamendo.com/track/12345/focus-playlist",
            "snippet": "Music track page with streaming preview",
            "displayLink": "jamendo.com",
        },
        {
            "title": "Focus discussion forum",
            "link": "https://example.com/forum/focus-playlist",
            "snippet": "论坛帖子与下载链接",
            "displayLink": "example.com",
        },
    ]

    filtered = filter_google_items(items)

    assert len(filtered) == 1
    assert filtered[0]["link"].startswith("https://www.jamendo.com/track/")


def test_map_google_item_to_result_marks_supplement_as_indexed_only():
    item = {
        "title": "Tech Podcast Episode 42",
        "link": "https://podcasts.apple.com/cn/podcast/tech-show/id42?i=10001",
        "snippet": "Podcast episode about AI systems",
        "displayLink": "podcasts.apple.com",
        "pagemap": {
            "metatags": [{"author": "AI Show", "og:site_name": "Apple Podcasts"}],
            "cse_thumbnail": [{"src": "https://img.example.com/podcast.jpg"}],
        },
    }

    result = map_google_item_to_result(item)

    assert result["source"] == "google"
    assert result["media_type"] == "audio"
    assert result["media_subtype"] == "podcast_episode"
    assert result["availability"] == "indexed_only"
    assert result["is_playable"] is False
