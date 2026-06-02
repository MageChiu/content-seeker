import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../models/search_result.dart';
import '../settings/settings_provider.dart';

class QueryRewriteResult {
  final String? effectiveQuery;
  final bool applied;

  const QueryRewriteResult({
    required this.effectiveQuery,
    required this.applied,
  });
}

class ResultRerankResult {
  final List<SearchResult> results;
  final bool applied;

  const ResultRerankResult({
    required this.results,
    required this.applied,
  });
}

class ResultSummaryResult {
  final List<SearchResult> results;
  final int summaryCount;

  const ResultSummaryResult({
    required this.results,
    required this.summaryCount,
  });
}

void debugReportLocalLlm(
  String location,
  String msg,
  Map<String, dynamic> data,
) {
  if (!kDebugMode) return;

  final client = HttpClient();
  unawaited(() async {
    try {
      final request =
          await client.postUrl(Uri.parse('http://127.0.0.1:7777/event'));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'sessionId': 'local-llm-search',
        'runId': 'client-local-llm',
        'hypothesisId': 'LLM',
        'location': location,
        'msg': '[DEBUG] $msg',
        'data': data,
        'ts': DateTime.now().millisecondsSinceEpoch,
      }));
      final response = await request.close();
      await response.drain<void>();
      client.close();
    } catch (_) {
      client.close(force: true);
    }
  }());
}

class LocalLlmService {
  final SettingsProvider settings;

  const LocalLlmService({required this.settings});

  static const Duration _requestTimeout = Duration(seconds: 12);
  static const int _maxAttempts = 3;

  bool get isReady {
    if (!settings.useLocalLlm) return false;
    if (settings.llmBaseUrl.trim().isEmpty) return false;
    if (settings.llmModel.trim().isEmpty) return false;
    if (settings.llmProvider == LlmProviderType.ollama) return true;
    return settings.llmApiKey.trim().isNotEmpty;
  }

  Future<QueryRewriteResult> rewriteQuery(
    String query, {
    MediaType? mediaTypeFilter,
  }) async {
    if (!isReady) {
      return const QueryRewriteResult(effectiveQuery: null, applied: false);
    }

    final mediaLabel = switch (mediaTypeFilter) {
      MediaType.audio => '音频',
      MediaType.video => '视频',
      null => '综合媒体',
    };

    final prompt = '''
你是一个本地媒体搜索助手。请将用户查询改写成更适合搜索 API 的简洁关键词。
要求：
1. 保留原意，不要发散。
2. 不要解释，只返回一个改写后的查询字符串。
3. 如果原查询已经足够适合搜索，原样返回。
4. 当前目标媒体类型：$mediaLabel。

用户查询：$query
''';

    debugReportLocalLlm('local_llm_service.dart:rewriteQuery:start',
        'local llm rewrite start', {
      'query': query,
      'provider': settings.llmProvider.name,
      'baseUrl': settings.llmBaseUrl,
      'model': settings.llmModel,
      'mediaTypeFilter': mediaTypeFilter?.name,
    });

    final content = await _chat(prompt, maxTokens: 80);
    final rewritten = content?.trim();

    debugReportLocalLlm(
        'local_llm_service.dart:rewriteQuery:done', 'local llm rewrite done', {
      'query': query,
      'rewritten': rewritten,
    });

    if (rewritten == null || rewritten.isEmpty) {
      return const QueryRewriteResult(effectiveQuery: null, applied: false);
    }
    if (_normalize(rewritten) == _normalize(query)) {
      return QueryRewriteResult(effectiveQuery: rewritten, applied: false);
    }
    return QueryRewriteResult(effectiveQuery: rewritten, applied: true);
  }

  Future<ResultRerankResult> rerankResults(
    String originalQuery,
    List<SearchResult> results, {
    MediaType? mediaTypeFilter,
  }) async {
    if (!isReady || results.length < 2) {
      return ResultRerankResult(results: results, applied: false);
    }

    final topResults = results.take(8).toList(growable: false);
    final items = <String>[];
    for (var i = 0; i < topResults.length; i++) {
      final result = topResults[i];
      items.add(
        '${i + 1}. 标题: ${result.title}; 来源等级: ${result.sourceTierLabel}; '
        '可用性: ${result.availabilityLabel}; 播放方式: ${result.playbackKindLabel}; '
        '媒体类型: ${result.mediaSubtypeLabel}; 作者: ${result.artistOrAuthor}; '
        '专辑: ${result.albumOrSeries}; 描述: ${result.description}',
      );
    }

    final mediaLabel = switch (mediaTypeFilter) {
      MediaType.audio => '音频',
      MediaType.video => '视频',
      null => '综合媒体',
    };

    final prompt = '''
你是一个本地媒体搜索排序助手。请根据用户查询，对候选结果按相关性和结果质量重新排序。
排序原则：
1. 更正式的来源优先。
2. 可播放结果优先。
3. 信息更完整的结果优先。
4. 与用户查询更相关的结果优先。
5. 当前目标媒体类型：$mediaLabel。

输出要求：
1. 只返回 JSON 对象。
2. 格式为 {"ordered_indices":[1,2,3]}
3. ordered_indices 里只写编号，不要重复，不要解释。

用户查询：$originalQuery

候选结果：
${items.join('\n')}
''';

    debugReportLocalLlm(
      'local_llm_service.dart:rerankResults:start',
      'local llm rerank start',
      {
        'query': originalQuery,
        'candidateCount': topResults.length,
        'provider': settings.llmProvider.name,
        'baseUrl': settings.llmBaseUrl,
        'model': settings.llmModel,
      },
    );

    final content = await _chat(prompt, maxTokens: 220);
    final orderedIndices = _parseOrderedIndices(content);
    if (orderedIndices.isEmpty) {
      debugReportLocalLlm(
        'local_llm_service.dart:rerankResults:empty',
        'local llm rerank empty',
        {
          'query': originalQuery,
          'raw': content,
        },
      );
      return ResultRerankResult(results: results, applied: false);
    }

    final orderedSet = <int>{};
    final reorderedTop = <SearchResult>[];
    for (final index in orderedIndices) {
      if (index < 1 || index > topResults.length || !orderedSet.add(index)) {
        continue;
      }
      reorderedTop.add(topResults[index - 1]);
    }
    for (var i = 0; i < topResults.length; i++) {
      final oneBasedIndex = i + 1;
      if (!orderedSet.contains(oneBasedIndex)) {
        reorderedTop.add(topResults[i]);
      }
    }

    final reordered = <SearchResult>[
      ...reorderedTop,
      ...results.skip(topResults.length),
    ];

    final applied = !_sameOrdering(results, reordered);

    debugReportLocalLlm(
      'local_llm_service.dart:rerankResults:done',
      'local llm rerank done',
      {
        'query': originalQuery,
        'orderedIndices': orderedIndices,
        'applied': applied,
      },
    );

    return ResultRerankResult(results: reordered, applied: applied);
  }

  Future<ResultSummaryResult> summarizeResults(
    String originalQuery,
    List<SearchResult> results, {
    MediaType? mediaTypeFilter,
  }) async {
    if (!isReady || results.isEmpty) {
      return ResultSummaryResult(results: results, summaryCount: 0);
    }

    final topResults = results.take(5).toList(growable: false);
    final items = <String>[];
    for (var i = 0; i < topResults.length; i++) {
      final result = topResults[i];
      items.add(
        '${i + 1}. 标题: ${result.title}; 来源: ${result.sourceLabel}; '
        '类型: ${result.mediaSubtypeLabel}; 作者: ${result.artistOrAuthor}; '
        '专辑: ${result.albumOrSeries}; 描述: ${result.description}',
      );
    }

    final mediaLabel = switch (mediaTypeFilter) {
      MediaType.audio => '音频',
      MediaType.video => '视频',
      null => '综合媒体',
    };

    final prompt = '''
你是一个本地媒体搜索助手。请基于用户查询，为候选结果生成简短摘要。
要求：
1. 只返回 JSON 数组。
2. 格式为 [{"index": 1, "summary": "..."}, ...]
3. summary 使用中文，控制在 30 个字以内。
4. 只为最相关的结果生成摘要，不要超过 ${topResults.length} 条。
5. index 从 1 开始，对应结果编号。
6. 当前目标媒体类型：$mediaLabel。

用户查询：$originalQuery

候选结果：
${items.join('\n')}
''';

    debugReportLocalLlm('local_llm_service.dart:summarizeResults:start',
        'local llm summarize start', {
      'query': originalQuery,
      'resultCount': results.length,
      'summarizedCount': topResults.length,
      'provider': settings.llmProvider.name,
      'baseUrl': settings.llmBaseUrl,
      'model': settings.llmModel,
    });

    final content = await _chat(prompt, maxTokens: 300);
    final parsed = _parseSummaries(content);

    if (parsed.isEmpty) {
      debugReportLocalLlm('local_llm_service.dart:summarizeResults:empty',
          'local llm summarize empty', {
        'query': originalQuery,
        'raw': content,
      });
      return ResultSummaryResult(results: results, summaryCount: 0);
    }

    final summaryByIndex = <int, String>{};
    for (final item in parsed) {
      final index = item['index'];
      final summary = item['summary'];
      if (index is int && summary is String && summary.trim().isNotEmpty) {
        summaryByIndex[index] = summary.trim();
      }
    }

    final updated = <SearchResult>[];
    for (var i = 0; i < results.length; i++) {
      final result = results[i];
      final summary = summaryByIndex[i + 1];
      if (summary == null || summary.isEmpty) {
        updated.add(result);
        continue;
      }
      updated.add(
        result.copyWith(aiSummary: summary),
      );
    }

    debugReportLocalLlm('local_llm_service.dart:summarizeResults:done',
        'local llm summarize done', {
      'query': originalQuery,
      'summaryCount': summaryByIndex.length,
    });

    return ResultSummaryResult(
      results: updated,
      summaryCount: summaryByIndex.length,
    );
  }

  Future<String?> _chat(
    String prompt, {
    required int maxTokens,
  }) async {
    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        final baseUrl =
            settings.llmBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
        final uri = Uri.parse('$baseUrl/chat/completions');
        final response = await http
            .post(
              uri,
              headers: {
                'Content-Type': 'application/json',
                if (settings.llmApiKey.trim().isNotEmpty)
                  'Authorization': 'Bearer ${settings.llmApiKey.trim()}',
              },
              body: jsonEncode({
                'model': settings.llmModel.trim(),
                'messages': [
                  {
                    'role': 'system',
                    'content': '你是一个本地客户端媒体搜索助手。',
                  },
                  {
                    'role': 'user',
                    'content': prompt,
                  },
                ],
                'temperature': 0.2,
                'max_tokens': maxTokens,
                'response_format': {'type': 'json_object'},
              }),
            )
            .timeout(_requestTimeout);

        debugReportLocalLlm(
            'local_llm_service.dart:_chat:response', 'local llm response', {
          'attempt': attempt,
          'statusCode': response.statusCode,
          'bodyPreview': response.body.substring(
            0,
            response.body.length > 300 ? 300 : response.body.length,
          ),
        });

        if (response.statusCode < 200 || response.statusCode >= 300) {
          if (attempt == _maxAttempts) {
            return null;
          }
          continue;
        }

        final data = jsonDecode(response.body);
        if (data is! Map<String, dynamic>) {
          if (attempt == _maxAttempts) {
            return null;
          }
          continue;
        }
        final choices = data['choices'];
        if (choices is! List || choices.isEmpty) {
          if (attempt == _maxAttempts) {
            return null;
          }
          continue;
        }
        final first = choices.first;
        if (first is! Map) {
          if (attempt == _maxAttempts) {
            return null;
          }
          continue;
        }
        final message = first['message'];
        if (message is! Map) {
          if (attempt == _maxAttempts) {
            return null;
          }
          continue;
        }
        final content = message['content'];
        if (content is String && content.trim().isNotEmpty) {
          return content;
        }
      } on TimeoutException catch (e) {
        debugReportLocalLlm(
          'local_llm_service.dart:_chat:timeout',
          'local llm request timeout',
          {
            'attempt': attempt,
            'timeoutMs': _requestTimeout.inMilliseconds,
            'error': e.toString(),
          },
        );
      } catch (e) {
        debugReportLocalLlm(
            'local_llm_service.dart:_chat:error', 'local llm request failed', {
          'attempt': attempt,
          'error': e.toString(),
        });
      }
      if (attempt < _maxAttempts) {
        await Future<void>.delayed(Duration(milliseconds: 300 * attempt));
      }
    }
    return null;
  }

  List<Map<String, dynamic>> _parseSummaries(String? content) {
    final decoded = _tryDecodeJsonPayload(content);
    if (decoded is! List) {
      return const [];
    }
    return decoded
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  List<int> _parseOrderedIndices(String? content) {
    final decoded = _tryDecodeJsonPayload(content);
    if (decoded is! Map<String, dynamic>) {
      return const [];
    }
    final values = decoded['ordered_indices'];
    if (values is! List) {
      return const [];
    }
    return values
        .map((item) {
          if (item is int) return item;
          return int.tryParse('$item');
        })
        .whereType<int>()
        .toList(growable: false);
  }

  Object? _tryDecodeJsonPayload(String? content) {
    if (content == null || content.trim().isEmpty) {
      return null;
    }
    final normalized = content.trim();
    final withoutFence = normalized
        .replaceAll(RegExp(r'^```(?:json)?\s*'), '')
        .replaceAll(RegExp(r'\s*```$'), '')
        .trim();

    try {
      return jsonDecode(withoutFence);
    } catch (_) {
      final arrayStart = withoutFence.indexOf('[');
      final arrayEnd = withoutFence.lastIndexOf(']');
      if (arrayStart >= 0 && arrayEnd > arrayStart) {
        final arrayText = withoutFence.substring(arrayStart, arrayEnd + 1);
        try {
          return jsonDecode(arrayText);
        } catch (_) {}
      }
      final objectStart = withoutFence.indexOf('{');
      final objectEnd = withoutFence.lastIndexOf('}');
      if (objectStart >= 0 && objectEnd > objectStart) {
        final objectText = withoutFence.substring(objectStart, objectEnd + 1);
        try {
          return jsonDecode(objectText);
        } catch (_) {}
      }
      return null;
    }
  }

  bool _sameOrdering(List<SearchResult> a, List<SearchResult> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].source != b[i].source || a[i].id != b[i].id) {
        return false;
      }
    }
    return true;
  }

  String _normalize(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }
}
