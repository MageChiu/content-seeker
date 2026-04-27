// 通道 2: 走服务端统一搜索（多源 + LLM 增强）
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/search_source.dart';
import '../../../models/search_result.dart';

class ServerSearchSource implements SearchSource {
  final String baseUrl;
  final String? authToken;

  ServerSearchSource({required this.baseUrl, this.authToken});

  @override
  String get name => 'server';

  @override
  bool get isConfigured => baseUrl.isNotEmpty;

  @override
  Future<List<SearchResult>> search(
    String query, {
    int page = 1,
    int limit = 20,
    List<String>? sources,
    String? mediaTypePreference,
    bool enhanceWithLlm = true,
    bool enableWebSupplement = false,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/v1/search'),
        headers: {
          'Content-Type': 'application/json',
          if (authToken != null) 'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode({
          'query': query,
          'page': page,
          'limit': limit,
          'enhance_with_llm': enhanceWithLlm,
          if (mediaTypePreference != null && mediaTypePreference.isNotEmpty)
            'media_type_preference': mediaTypePreference,
          'enable_web_supplement': enableWebSupplement,
          if (sources != null && sources.isNotEmpty) 'sources': sources,
        }),
      );

      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body);
      final results = data['results'] as List? ?? [];
      return results
          .map((r) => SearchResult.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }
}
