import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/search_source.dart';
import '../../../models/search_result.dart';
import 'local_source_debug.dart';

class DeezerLocalSource implements SearchSource {
  static const int _maxAttempts = 3;
  static final LocalSourceRateLimitState _rateLimitState =
      LocalSourceRateLimitState();

  @override
  String get name => 'deezer_local';

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
        source: 'deezer',
        location: 'deezer_local_source.dart:search',
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
        final uri = Uri.https('api.deezer.com', '/search/track', {
          'q': query,
          'limit': '${limit.clamp(1, 50)}',
          'index': '${((page - 1).clamp(0, 999)) * limit}',
        });
        reportLocalSourceDebug(
          source: 'deezer',
          location: 'deezer_local_source.dart:search',
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
          source: 'deezer',
          location: 'deezer_local_source.dart:search',
          msg: 'response received',
          data: {
            'attempt': attempt,
            'statusCode': response.statusCode,
            'bodyPreview': bodyPreview(response.body),
          },
        );

        if (response.statusCode != 200) {
          throw LocalSourceHttpException(
            message: 'Deezer 搜索 HTTP 状态异常',
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
              final trackId = item['id'];
              if (trackId == null) {
                return null;
              }

              final previewUrl = '${item['preview'] ?? ''}'.trim();
              final linkUrl = '${item['link'] ?? ''}'.trim();
              final artist = Map<String, dynamic>.from(
                (item['artist'] as Map?) ?? const {},
              );
              final album = Map<String, dynamic>.from(
                (item['album'] as Map?) ?? const {},
              );
              final artistName = '${artist['name'] ?? ''}'.trim();
              final albumName = '${album['title'] ?? ''}'.trim();
              final title = '${item['title'] ?? ''}'.trim();

              return SearchResult(
                id: 'deezer-$trackId',
                title: _buildTitle(title, artistName),
                source: 'deezer',
                mediaType: MediaType.audio,
                mediaSubtype: MediaSubtype.musicTrack,
                thumbnailUrl:
                    '${album['cover_medium'] ?? album['cover'] ?? ''}'.trim(),
                durationSeconds: _readInt(item['duration']),
                playUrl: previewUrl.isNotEmpty ? previewUrl : linkUrl,
                playbackKind: previewUrl.isNotEmpty
                    ? SearchPlaybackKind.nativeStream
                    : SearchPlaybackKind.externalOpen,
                isPlayable: previewUrl.isNotEmpty,
                availability: previewUrl.isNotEmpty
                    ? ResultAvailability.preview
                    : ResultAvailability.indexedOnly,
                sourceTier: SourceTier.officialApi,
                canonicalUrl: linkUrl.isNotEmpty ? linkUrl : previewUrl,
                artistOrAuthor: artistName,
                albumOrSeries: albumName,
                description: [
                  if (artistName.isNotEmpty) artistName,
                  if (albumName.isNotEmpty) albumName,
                ].join(' / '),
              );
            })
            .whereType<SearchResult>()
            .toList(growable: false);

        _rateLimitState.onSuccess();
        reportLocalSourceDebug(
          source: 'deezer',
          location: 'deezer_local_source.dart:search',
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
          source: 'deezer',
          location: 'deezer_local_source.dart:search',
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
            source: 'deezer',
            location: 'deezer_local_source.dart:search',
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
          source: 'deezer',
          location: 'deezer_local_source.dart:search',
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
      source: 'deezer',
      location: 'deezer_local_source.dart:search',
      msg: 'search degraded to empty result',
      data: {
        'query': query,
        'error': lastError?.toString(),
      },
    );
    return [];
  }

  static String _buildTitle(String title, String artistName) {
    if (title.isNotEmpty && artistName.isNotEmpty) {
      return '$title - $artistName';
    }
    return title.isNotEmpty ? title : artistName;
  }

  static int _readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse('$value') ?? 0;
  }
}
