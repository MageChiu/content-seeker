import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/search_source.dart';
import '../../../models/search_result.dart';
import 'local_source_debug.dart';
import 'media_search_query_helper.dart';

class DailymotionLocalSource implements SearchSource {
  static const int _maxAttempts = 3;
  static final LocalSourceRateLimitState _rateLimitState =
      LocalSourceRateLimitState();

  @override
  String get name => 'dailymotion_local';

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
        source: 'dailymotion',
        location: 'dailymotion_local_source.dart:search',
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
        final uri = Uri.https('api.dailymotion.com', '/videos', {
          'search': effectiveQuery,
          'page': '$page',
          'limit': '${limit.clamp(1, 50)}',
          'fields':
              'id,title,url,thumbnail_360_url,duration,owner.screenname,description',
        });
        reportLocalSourceDebug(
          source: 'dailymotion',
          location: 'dailymotion_local_source.dart:search',
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
          source: 'dailymotion',
          location: 'dailymotion_local_source.dart:search',
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
            message: 'Dailymotion 搜索 HTTP 状态异常',
            uri: uri,
            statusCode: response.statusCode,
            bodyPreview: bodyPreview(response.body),
            retryAfterSeconds: parseRetryAfterSeconds(response),
          );
        }

        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final items = data['list'] as List? ?? [];
        final rawCount = items.length;
        final results = items
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .map((item) {
              final videoId = '${item['id'] ?? ''}'.trim();
              if (videoId.isEmpty) {
                return null;
              }

              final canonicalUrl =
                  '${item['url'] ?? 'https://www.dailymotion.com/video/$videoId'}'
                      .trim();

              return SearchResult(
                id: videoId,
                title: '${item['title'] ?? ''}'.trim(),
                source: 'dailymotion',
                mediaType: MediaType.video,
                mediaSubtype: MediaSubtype.video,
                thumbnailUrl: '${item['thumbnail_360_url'] ?? ''}'.trim(),
                durationSeconds: _readInt(item['duration']),
                playUrl: canonicalUrl,
                playbackKind: SearchPlaybackKind.externalOpen,
                isPlayable: canonicalUrl.isNotEmpty,
                availability: canonicalUrl.isNotEmpty
                    ? ResultAvailability.available
                    : ResultAvailability.indexedOnly,
                sourceTier: SourceTier.officialApi,
                canonicalUrl: canonicalUrl,
                artistOrAuthor: '${item['owner.screenname'] ?? ''}'.trim(),
                albumOrSeries: '',
                description: '${item['description'] ?? ''}'.trim(),
              );
            })
            .whereType<SearchResult>()
            .toList(growable: false);

        _rateLimitState.onSuccess();
        reportLocalSourceDebug(
          source: 'dailymotion',
          location: 'dailymotion_local_source.dart:search',
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
          source: 'dailymotion',
          location: 'dailymotion_local_source.dart:search',
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
            source: 'dailymotion',
            location: 'dailymotion_local_source.dart:search',
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
          source: 'dailymotion',
          location: 'dailymotion_local_source.dart:search',
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
      source: 'dailymotion',
      location: 'dailymotion_local_source.dart:search',
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
