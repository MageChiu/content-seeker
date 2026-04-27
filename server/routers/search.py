"""搜索路由 - 编排多源搜索 + LLM 增强"""

import asyncio
import logging

from fastapi import APIRouter
from models.schemas import SearchIntent, SearchRequest, SearchResponse
from services.google_search_service import GoogleSearchService
from services.jamendo_service import JamendoService
from services.llm_service import LLMService
from services.podcast_service import PodcastService
from services.search_orchestrator import (
    detect_search_intent,
    select_sources,
    sort_and_deduplicate_results,
)
from services.youtube_service import YouTubeService
from services.bilibili_service import BilibiliService
from services.itunes_service import ItunesService

logger = logging.getLogger(__name__)
router = APIRouter()


def _build_search_task(name: str, service, query: str, limit: int, intent: SearchIntent):
    if name == "itunes":
        return service.search(
            query,
            limit=limit,
            allow_broad_match=intent == SearchIntent.audio,
        )
    return service.search(query, limit=limit)


@router.post("/search", response_model=SearchResponse)
async def search(req: SearchRequest):
    llm = LLMService()

    # Step 1: LLM 改写 query
    query_rewritten = None
    search_query = req.query
    if req.enhance_with_llm:
        rewritten = await llm.rewrite_query(req.query)
        if rewritten != req.query:
            search_query = rewritten
            query_rewritten = rewritten

    # Step 2: 媒体意图识别 + 按意图选择源
    intent = detect_search_intent(req.query, req.media_type_preference)
    source_map = {
        "youtube": YouTubeService(),
        "bilibili": BilibiliService(),
        "itunes": ItunesService(),
        "jamendo": JamendoService(),
        "podcast": PodcastService(),
        "google": GoogleSearchService(),
    }

    selected_source_names = select_sources(
        intent=intent,
        requested_sources=req.sources,
        enable_web_supplement=req.enable_web_supplement,
    )
    active_sources = {
        name: source_map[name]
        for name in selected_source_names
        if name in source_map
    }

    tasks = [
        _build_search_task(name, svc, search_query, req.limit, intent)
        for name, svc in active_sources.items()
    ]
    raw_results = await asyncio.gather(*tasks, return_exceptions=True)

    # 合并，过滤失败的
    all_results = []
    for r in raw_results:
        if isinstance(r, list):
            all_results.extend(r)
        elif isinstance(r, Exception):
            logger.warning(f"Source search failed: {r}")

    # Step 3: 去重排序，优先正式源和可播放结果
    all_results = sort_and_deduplicate_results(all_results, intent)

    # Step 4: LLM 重排 + 摘要
    if req.enhance_with_llm and all_results:
        all_results = await llm.rerank_and_summarize(req.query, all_results)

    start = max(req.page - 1, 0) * req.limit
    end = start + req.limit
    paged_results = all_results[start:end]

    return SearchResponse(
        results=paged_results,
        total=len(all_results),
        query_rewritten=query_rewritten,
    )
