"""LLM 编排服务：Query 改写 + 结果重排"""

import os
import json
import logging
from openai import AsyncOpenAI

logger = logging.getLogger(__name__)


class LLMService:
    def __init__(self):
        api_key = os.environ.get("OPENAI_API_KEY", "")
        self.enabled = bool(api_key and api_key != "sk-your-openai-key")
        if self.enabled:
            self.client = AsyncOpenAI(api_key=api_key)

    async def rewrite_query(self, user_query: str) -> str:
        """用 LLM 优化搜索关键词"""
        if not self.enabled:
            return user_query

        try:
            resp = await self.client.chat.completions.create(
                model="gpt-4o-mini",
                messages=[
                    {
                        "role": "system",
                        "content": (
                            "你是一个搜索 query 优化器。用户输入自然语言描述，你输出优化后的搜索关键词。\n"
                            "规则：\n"
                            "- 提取核心关键词\n"
                            "- 补充同义词或英文对照（如果有助于搜索）\n"
                            "- 去除口语化表达\n"
                            "- 只输出优化后的 query，不要解释"
                        ),
                    },
                    {"role": "user", "content": user_query},
                ],
                max_tokens=100,
            )
            return resp.choices[0].message.content.strip()
        except Exception as e:
            logger.warning(f"LLM rewrite failed: {e}")
            return user_query

    async def rerank_and_summarize(
        self, original_query: str, results: list[dict]
    ) -> list[dict]:
        """用 LLM 对搜索结果重排序并生成推荐理由"""
        if not self.enabled or not results:
            return results

        # 只取前 15 条做重排，控制 token 消耗
        candidates = results[:15]
        brief = [
            {"index": i, "title": r.get("title", ""), "description": r.get("description", "")[:100]}
            for i, r in enumerate(candidates)
        ]

        try:
            resp = await self.client.chat.completions.create(
                model="gpt-4o-mini",
                messages=[
                    {
                        "role": "system",
                        "content": (
                            "你是搜索结果排序器。根据用户需求对结果重排序，并为每个结果生成一句推荐理由。\n"
                            '返回 JSON: {"ranked": [{"index": 0, "summary": "推荐理由"}, ...]}\n'
                            "按相关性从高到低排列。"
                        ),
                    },
                    {
                        "role": "user",
                        "content": f"用户需求: {original_query}\n\n搜索结果:\n{json.dumps(brief, ensure_ascii=False)}",
                    },
                ],
                max_tokens=1000,
                response_format={"type": "json_object"},
            )

            ranking = json.loads(resp.choices[0].message.content)
            ranked_items = ranking.get("ranked", [])

            reranked = []
            for item in ranked_items:
                idx = item.get("index", -1)
                if 0 <= idx < len(candidates):
                    candidates[idx]["ai_summary"] = item.get("summary", "")
                    reranked.append(candidates[idx])

            # 加上未被排到的结果
            ranked_indices = {item.get("index") for item in ranked_items}
            for i, r in enumerate(candidates):
                if i not in ranked_indices:
                    reranked.append(r)

            return reranked
        except Exception as e:
            logger.warning(f"LLM rerank failed: {e}")
            return results
