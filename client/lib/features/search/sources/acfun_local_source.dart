import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/search_source.dart';
import '../../../models/search_result.dart';
import 'local_source_debug.dart';
import 'media_search_query_helper.dart';

class AcFunLocalSource implements SearchSource {
  static const int _maxAttempts = 3;
  static final LocalSourceRateLimitState _rateLimitState =
      LocalSourceRateLimitState();

  @override
  String get name => 'acfun_local';

  @override
  bool get isConfigured => true;

  @override
  Future<List<SearchResult>> search(
    String query, {
    int page = 1,
    int limit = 20,
  }) async {
    if (_rateLimitState.isCoolingDown) {
      reportLocalSourceDebug(
        source: 'acfun',
        location: 'acfun_local_source.dart:search',
        msg: 'skip search during cooldown',
        data: {
          'query': query,
          'remainingMs': _rateLimitState.remainingCooldown.inMilliseconds,
        },
      );
      return [];
    }

    for (final effectiveQuery in buildMediaSearchQueries(query, maxVariants: 4)) {
      final results = await _searchSingleQuery(
        originalQuery: query,
        effectiveQuery: effectiveQuery,
        page: page,
        limit: limit,
      );
      if (results.isNotEmpty || _rateLimitState.isCoolingDown) {
        return results;
      }
    }
    return [];
  }

  Future<List<SearchResult>> _searchSingleQuery({
    required String originalQuery,
    required String effectiveQuery,
    required int page,
    required int limit,
  }) async {
    Object? lastError;
    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        final uri = Uri.https('www.acfun.cn', '/rest/pc-direct/search/video', {
          'keyword': effectiveQuery,
          'page': '$page',
          'pageSize': '$limit',
        });
        reportLocalSourceDebug(
          source: 'acfun',
          location: 'acfun_local_source.dart:search',
          msg: 'request start',
          data: {
            'query': originalQuery,
            'effectiveQuery': effectiveQuery,
            'page': page,
            'limit': limit,
            'attempt': attempt,
            'uri': uri.toString(),
          },
        );

        final response = await http.get(uri, headers: {
          'User-Agent':
              'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36',
          'Referer': 'https://www.acfun.cn',
        }).timeout(const Duration(seconds: 12));

        reportLocalSourceDebug(
          source: 'acfun',
          location: 'acfun_local_source.dart:search',
          msg: 'response received',
          data: {
            'attempt': attempt,
            'effectiveQuery': effectiveQuery,
            'statusCode': response.statusCode,
            'bodyPreview': bodyPreview(response.body),
          },
        );

        if (response.statusCode != 200) {
          throw LocalSourceHttpException(
            message: 'AcFun 搜索 HTTP 状态异常',
            uri: uri,
            statusCode: response.statusCode,
            bodyPreview: bodyPreview(response.body),
            retryAfterSeconds: parseRetryAfterSeconds(response),
          );
        }

        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['result'] != 0) {
          throw LocalSourceHttpException(
            message: 'AcFun 搜索业务错误: result=${data['result']}',
            uri: uri,
            statusCode: response.statusCode,
            bodyPreview: bodyPreview(response.body),
          );
        }

        final items = (data['webSearchResult']?['webSearchVideoResult']
                ?['listInfo'] as List?) ??
            [];
        final rawCount = items.length;
        final results = items
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .map((item) {
              final contentId = '${item['contentId'] ?? ''}'.trim();
              if (contentId.isEmpty) return null;

              final rawTitle = '${item['title'] ?? ''}'.trim();
              final title = rawTitle.replaceAll(RegExp(r'<[^>]*>'), '');
              final coverUrl = '${item['coverUrl'] ?? ''}'.trim();
              final durationMs = _readInt(item['duration']);
              final userName = '${item['userName'] ?? ''}'.trim();
              final description = '${item['description'] ?? ''}'.trim();
              final playUrl = 'https://www.acfun.cn/v/ac$contentId';

              return SearchResult(
                id: contentId,
                title: title,
                source: 'acfun',
                mediaType: MediaType.video,
                mediaSubtype: MediaSubtype.video,
                thumbnailUrl: coverUrl,
                durationSeconds: durationMs ~/ 1000,
                playUrl: playUrl,
                playbackKind: SearchPlaybackKind.externalOpen,
                isPlayable: true,
                availability: ResultAvailability.available,
                sourceTier: SourceTier.publicApi,
                canonicalUrl: playUrl,
                artistOrAuthor: userName,
                albumOrSeries: '',
                description: description,
              );
            })
            .whereType<SearchResult>()
            .toList(growable: false);

        _rateLimitState.onSuccess();
        reportLocalSourceDebug(
          source: 'acfun',
          location: 'acfun_local_source.dart:search',
          msg: 'response parsed',
          data: {
            'attempt': attempt,
            'effectiveQuery': effectiveQuery,
            'rawItemCount': rawCount,
            'resultCount': results.length,
            'filteredOutCount': rawCount - results.length,
          },
        );
        return results;
      } catch (error) {
        lastError = error;
        reportLocalSourceDebug(
          source: 'acfun',
          location: 'acfun_local_source.dart:search',
          msg: 'request failed',
          data: {
            'query': originalQuery,
            'effectiveQuery': effectiveQuery,
            'attempt': attempt,
            'error': error.toString(),
          },
        );

        if (isRateLimitedLocalSourceError(error) &&
            error is LocalSourceHttpException) {
          final cooldown = _rateLimitState.activateCooldown(
            retryAfterSeconds: error.retryAfterSeconds,
          );
          reportLocalSourceDebug(
            source: 'acfun',
            location: 'acfun_local_source.dart:search',
            msg: 'rate limited, cooldown activated',
            data: {
              'attempt': attempt,
              'effectiveQuery': effectiveQuery,
              'statusCode': error.statusCode,
              'retryAfterSeconds': error.retryAfterSeconds,
              'cooldownMs': cooldown.inMilliseconds,
            },
          );
        }

        if (attempt >= _maxAttempts ||
            !isRetryableLocalSourceError(error) ||
            _rateLimitState.isCoolingDown) {
          break;
        }

        final delay = retryDelayForAttempt(
          attempt,
          rateLimited: isRateLimitedLocalSourceError(error),
        );
        reportLocalSourceDebug(
          source: 'acfun',
          location: 'acfun_local_source.dart:search',
          msg: 'retry scheduled',
          data: {
            'attempt': attempt,
            'effectiveQuery': effectiveQuery,
            'nextAttempt': attempt + 1,
            'delayMs': delay.inMilliseconds,
          },
        );
        await Future<void>.delayed(delay);
      }
    }
    reportLocalSourceDebug(
      source: 'acfun',
      location: 'acfun_local_source.dart:search',
      msg: 'search degraded to empty result',
      data: {
        'query': originalQuery,
        'effectiveQuery': effectiveQuery,
        'error': lastError?.toString(),
      },
    );
    return [];
  }

  static int _readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse('$value') ?? 0;
  }
}
