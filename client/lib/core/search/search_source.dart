// lib/core/search/search_source.dart

/// 统一搜索结果
class SearchResult {
  final String id;
  final String title;
  final String source;          // "youtube" / "bilibili" / "spotify"
  final MediaType mediaType;    // video / audio
  final String thumbnailUrl;
  final Duration duration;
  final String? playUrl;
  final List<TimedSegment> highlights;  // 命中的时间段
  final String? aiSummary;      // LLM 生成的推荐理由

  SearchResult({...});
}

class TimedSegment {
  final Duration timestamp;
  final String text;
  TimedSegment({required this.timestamp, required this.text});
}

/// 搜索源接口 - 所有源实现这个
abstract class SearchSource {
  String get name;
  Future<List<SearchResult>> search(String query, {int page = 1, int limit = 20});
  bool get isConfigured;  // 用户是否已配置该源
}