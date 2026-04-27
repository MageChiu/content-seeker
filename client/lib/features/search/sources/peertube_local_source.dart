import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/search_source.dart';
import '../../../models/search_result.dart';
import 'local_source_debug.dart';

class PeerTubeLocalSource implements SearchSource {
  static const int _maxAttempts = 3;
  static final LocalSourceRateLimitState _rateLimitState =
      LocalSourceRateLimitState();

  final String instanceUrl;

  PeerTubeLocalSource({this.instanceUrl = 'https://search.joinpeertube.org'});

  @override
  String get name => 'peertube_local';

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
        source: 'peertube',
        location: 'peertube_local_source.dart:search',
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
        final start = (page - 1) * limit;
        final uri = Uri.parse(
          '$instanceUrl/api/v1/search/videos'
          '?search=${Uri.encodeQueryComponent(query)}'
          '&count=${limit.clamp(1, 100)}'
          '&start=$start',
        );
        reportLocalSourceDebug(
          source: 'peertube',
          location: 'peertube_local_source.dart:search',
          msg: 'request start',
          data: {
            'query': query,
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
          source: 'peertube',
          location: 'peertube_local_source.dart:search',
          msg: 'response received',
          data: {
            'attempt': attempt,
            'statusCode': response.statusCode,
            'bodyPreview': bodyPreview(response.body),
          },
        );

        if (response.statusCode != 200) {
          throw LocalSourceHttpException(
            message: 'PeerTube 搜索 HTTP 状态异常',
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
              final videoId = '${item['uuid'] ?? ''}'.trim();
              if (videoId.isEmpty) return null;

              final videoUrl = '${item['url'] ?? ''}'.trim();
              final shortUUID = '${item['shortUUID'] ?? ''}'.trim();

              // Determine play URL
              String playUrl = videoUrl;
              if (playUrl.isEmpty && shortUUID.isNotEmpty) {
                playUrl = '$instanceUrl/w/$shortUUID';
              }

              // Determine thumbnail URL
              final thumbnailPath = '${item['thumbnailPath'] ?? ''}'.trim();
              String thumbnailUrl = '';
              if (thumbnailPath.isNotEmpty) {
                if (thumbnailPath.startsWith('http')) {
                  thumbnailUrl = thumbnailPath;
                } else {
                  // Prepend host from video url, or fallback to instanceUrl
                  final host = _extractHost(videoUrl) ?? instanceUrl;
                  thumbnailUrl = '$host$thumbnailPath';
                }
              }

              // Account and channel info
              final account = item['account'] as Map?;
              final channel = item['channel'] as Map?;
              final accountName = '${account?['displayName'] ?? ''}'.trim();
              final channelName = '${channel?['displayName'] ?? ''}'.trim();

              final artistOrAuthor =
                  accountName.isNotEmpty ? accountName : channelName;
              final albumOrSeries =
                  (channelName.isNotEmpty && channelName != accountName)
                      ? channelName
                      : '';

              // Description (truncate if too long)
              String description = '${item['description'] ?? ''}'.trim();
              if (description.length > 300) {
                description = '${description.substring(0, 297)}...';
              }

              return SearchResult(
                id: videoId,
                title: '${item['name'] ?? ''}'.trim(),
                source: 'peertube',
                mediaType: MediaType.video,
                mediaSubtype: MediaSubtype.video,
                thumbnailUrl: thumbnailUrl,
                durationSeconds: _readInt(item['duration']),
                playUrl: playUrl,
                playbackKind: SearchPlaybackKind.embeddedWeb,
                isPlayable: true,
                availability: ResultAvailability.available,
                sourceTier: SourceTier.publicApi,
                canonicalUrl: videoUrl,
                artistOrAuthor: artistOrAuthor,
                albumOrSeries: albumOrSeries,
                description: description,
              );
            })
            .whereType<SearchResult>()
            .toList(growable: false);

        _rateLimitState.onSuccess();
        reportLocalSourceDebug(
          source: 'peertube',
          location: 'peertube_local_source.dart:search',
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
          source: 'peertube',
          location: 'peertube_local_source.dart:search',
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
            source: 'peertube',
            location: 'peertube_local_source.dart:search',
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
          source: 'peertube',
          location: 'peertube_local_source.dart:search',
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
      source: 'peertube',
      location: 'peertube_local_source.dart:search',
      msg: 'search degraded to empty result',
      data: {
        'query': query,
        'error': lastError?.toString(),
      },
    );
    return [];
  }

  static String? _extractHost(String url) {
    if (url.isEmpty) return null;
    final parsed = Uri.tryParse(url);
    if (parsed == null || !parsed.hasScheme) return null;
    return '${parsed.scheme}://${parsed.host}';
  }

  static int _readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse('$value') ?? 0;
  }
}
