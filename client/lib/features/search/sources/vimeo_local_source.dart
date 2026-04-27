import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/search_source.dart';
import '../../../models/search_result.dart';
import 'local_source_debug.dart';

class VimeoLocalSource implements SearchSource {
  static const int _maxAttempts = 3;
  static final LocalSourceRateLimitState _rateLimitState =
      LocalSourceRateLimitState();

  final String accessToken;

  VimeoLocalSource({required this.accessToken});

  @override
  String get name => 'vimeo_local';

  @override
  bool get isConfigured => accessToken.isNotEmpty;

  @override
  Future<List<SearchResult>> search(
    String query, {
    int page = 1,
    int limit = 20,
  }) async {
    if (_rateLimitState.isCoolingDown) {
      reportLocalSourceDebug(
        source: 'vimeo',
        location: 'vimeo_local_source.dart:search',
        msg: 'skip search during cooldown',
        data: {
          'query': query,
          'remainingMs': _rateLimitState.remainingCooldown.inMilliseconds,
        },
      );
      return [];
    }

    Object? lastError;
    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        final uri = Uri.https('api.vimeo.com', '/videos', {
          'query': query,
          'per_page': '${limit.clamp(1, 50)}',
          'page': '$page',
        });
        reportLocalSourceDebug(
          source: 'vimeo',
          location: 'vimeo_local_source.dart:search',
          msg: 'request start',
          data: {
            'query': query,
            'page': page,
            'limit': limit,
            'attempt': attempt,
            'uri': uri.toString(),
          },
        );

        final response = await http.get(uri, headers: {
          'Authorization': 'Bearer $accessToken',
        }).timeout(
          const Duration(seconds: 12),
        );
        reportLocalSourceDebug(
          source: 'vimeo',
          location: 'vimeo_local_source.dart:search',
          msg: 'response received',
          data: {
            'attempt': attempt,
            'statusCode': response.statusCode,
            'bodyPreview': bodyPreview(response.body),
          },
        );

        if (response.statusCode != 200) {
          throw LocalSourceHttpException(
            message: 'Vimeo 搜索 HTTP 状态异常',
            uri: uri,
            statusCode: response.statusCode,
            bodyPreview: bodyPreview(response.body),
            retryAfterSeconds: parseRetryAfterSeconds(response),
          );
        }

        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final items = data['data'] as List? ?? [];
        final rawCount = items.length;
        final results = items
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .map((item) {
              final videoUri = '${item['uri'] ?? ''}'.trim();
              final videoId = videoUri.split('/').last;
              if (videoId.isEmpty) {
                return null;
              }

              final link = '${item['link'] ?? ''}'.trim();
              final thumbnailUrl = _extractThumbnail(item);
              final user = item['user'] as Map<String, dynamic>?;

              return SearchResult(
                id: videoId,
                title: '${item['name'] ?? ''}'.trim(),
                source: 'vimeo',
                mediaType: MediaType.video,
                mediaSubtype: MediaSubtype.video,
                thumbnailUrl: thumbnailUrl,
                durationSeconds: _readInt(item['duration']),
                playUrl: link,
                playbackKind: SearchPlaybackKind.externalOpen,
                isPlayable: link.isNotEmpty,
                availability: ResultAvailability.available,
                sourceTier: SourceTier.officialApi,
                canonicalUrl: link,
                artistOrAuthor: '${user?['name'] ?? ''}'.trim(),
                albumOrSeries: '',
                description: '${item['description'] ?? ''}'.trim(),
              );
            })
            .whereType<SearchResult>()
            .toList(growable: false);

        _rateLimitState.onSuccess();
        reportLocalSourceDebug(
          source: 'vimeo',
          location: 'vimeo_local_source.dart:search',
          msg: 'response parsed',
          data: {
            'attempt': attempt,
            'rawItemCount': rawCount,
            'resultCount': results.length,
            'filteredOutCount': rawCount - results.length,
          },
        );
        return results;
      } catch (error) {
        lastError = error;
        reportLocalSourceDebug(
          source: 'vimeo',
          location: 'vimeo_local_source.dart:search',
          msg: 'request failed',
          data: {
            'query': query,
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
            source: 'vimeo',
            location: 'vimeo_local_source.dart:search',
            msg: 'rate limited, cooldown activated',
            data: {
              'attempt': attempt,
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
          source: 'vimeo',
          location: 'vimeo_local_source.dart:search',
          msg: 'retry scheduled',
          data: {
            'attempt': attempt,
            'nextAttempt': attempt + 1,
            'delayMs': delay.inMilliseconds,
          },
        );
        await Future<void>.delayed(delay);
      }
    }
    reportLocalSourceDebug(
      source: 'vimeo',
      location: 'vimeo_local_source.dart:search',
      msg: 'search degraded to empty result',
      data: {
        'query': query,
        'error': lastError?.toString(),
      },
    );
    return [];
  }

  static String _extractThumbnail(Map<String, dynamic> item) {
    final pictures = item['pictures'] as Map<String, dynamic>?;
    if (pictures == null) return '';
    final sizes = pictures['sizes'] as List?;
    if (sizes == null || sizes.isEmpty) return '';
    // Pick a medium size (~640 width) or fall back to the last available.
    for (final size in sizes) {
      if (size is Map && (size['width'] as int?) == 640) {
        return '${size['link'] ?? ''}'.trim();
      }
    }
    // Fallback: pick the largest available.
    final last = sizes.last;
    if (last is Map) {
      return '${last['link'] ?? ''}'.trim();
    }
    return '';
  }

  static int _readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse('$value') ?? 0;
  }
}
