import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/search_source.dart';
import '../../../models/search_result.dart';
import 'local_source_debug.dart';
import 'media_search_query_helper.dart';

class YoukuLocalSource implements SearchSource {
  static const int _maxAttempts = 3;
  static final LocalSourceRateLimitState _rateLimitState =
      LocalSourceRateLimitState();

  final String clientId;

  YoukuLocalSource({required this.clientId});

  @override
  String get name => 'youku_local';

  @override
  bool get isConfigured => clientId.isNotEmpty;

  @override
  Future<List<SearchResult>> search(
    String query, {
    int page = 1,
    int limit = 20,
  }) async {
    if (_rateLimitState.isCoolingDown) {
      reportLocalSourceDebug(
        source: 'youku',
        location: 'youku_local_source.dart:search',
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
        final uri = Uri.https(
          'openapi.youku.com',
          '/v2/searches/video/by_keyword.json',
          {
            'client_id': clientId,
            'keyword': effectiveQuery,
            'page': '$page',
            'count': '$limit',
          },
        );
        reportLocalSourceDebug(
          source: 'youku',
          location: 'youku_local_source.dart:search',
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

        final response = await http.get(uri).timeout(
          const Duration(seconds: 12),
        );
        reportLocalSourceDebug(
          source: 'youku',
          location: 'youku_local_source.dart:search',
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
            message: 'Youku 搜索 HTTP 状态异常',
            uri: uri,
            statusCode: response.statusCode,
            bodyPreview: bodyPreview(response.body),
            retryAfterSeconds: parseRetryAfterSeconds(response),
          );
        }

        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final items = data['videos'] as List? ?? [];
        final rawCount = items.length;
        final results = items
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .map((item) {
              final videoId = '${item['id'] ?? ''}'.trim();
              if (videoId.isEmpty) return null;

              final link = '${item['link'] ?? ''}'.trim();
              final userName = item['user'] is Map
                  ? '${(item['user'] as Map)['name'] ?? ''}'.trim()
                  : '';

              return SearchResult(
                id: videoId,
                title: '${item['title'] ?? ''}'.trim(),
                source: 'youku',
                mediaType: MediaType.video,
                mediaSubtype: MediaSubtype.video,
                thumbnailUrl: '${item['thumbnail'] ?? ''}'.trim(),
                durationSeconds: _parseDuration('${item['duration'] ?? ''}'),
                playUrl: link,
                playbackKind: SearchPlaybackKind.externalOpen,
                isPlayable: link.isNotEmpty,
                availability: ResultAvailability.available,
                sourceTier: SourceTier.officialApi,
                canonicalUrl: link,
                artistOrAuthor: userName,
                albumOrSeries: '',
                description: '${item['description'] ?? ''}'.trim(),
              );
            })
            .whereType<SearchResult>()
            .toList(growable: false);

        _rateLimitState.onSuccess();
        reportLocalSourceDebug(
          source: 'youku',
          location: 'youku_local_source.dart:search',
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
          source: 'youku',
          location: 'youku_local_source.dart:search',
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
            source: 'youku',
            location: 'youku_local_source.dart:search',
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
          source: 'youku',
          location: 'youku_local_source.dart:search',
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
      source: 'youku',
      location: 'youku_local_source.dart:search',
      msg: 'search degraded to empty result',
      data: {
        'query': originalQuery,
        'effectiveQuery': effectiveQuery,
        'error': lastError?.toString(),
      },
    );
    return [];
  }

  static int _parseDuration(String d) {
    if (d.isEmpty) return 0;
    try {
      final parts = d.split(':');
      if (parts.length == 2) {
        return int.parse(parts[0]) * 60 + int.parse(parts[1]);
      } else if (parts.length == 3) {
        return int.parse(parts[0]) * 3600 +
            int.parse(parts[1]) * 60 +
            int.parse(parts[2]);
      }
    } catch (_) {}
    return 0;
  }
}
