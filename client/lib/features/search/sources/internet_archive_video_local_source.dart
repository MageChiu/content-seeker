import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/search_source.dart';
import '../../../models/search_result.dart';
import 'local_source_debug.dart';

class InternetArchiveVideoLocalSource implements SearchSource {
  static const int _maxAttempts = 3;
  static final LocalSourceRateLimitState _rateLimitState =
      LocalSourceRateLimitState();

  @override
  String get name => 'internet_archive_video_local';

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
        source: 'internet_archive_video',
        location: 'internet_archive_video_local_source.dart:search',
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
        final uri = Uri.https('archive.org', '/advancedsearch.php', {
          'q': _buildQuery(query),
          'fl[]': 'identifier,title,description,creator',
          'rows': '${limit.clamp(1, 20)}',
          'page': '$page',
          'sort[]': 'downloads desc',
          'output': 'json',
        });
        reportLocalSourceDebug(
          source: 'internet_archive_video',
          location: 'internet_archive_video_local_source.dart:search',
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
          source: 'internet_archive_video',
          location: 'internet_archive_video_local_source.dart:search',
          msg: 'response received',
          data: {
            'attempt': attempt,
            'statusCode': response.statusCode,
            'bodyPreview': bodyPreview(response.body),
          },
        );
        if (response.statusCode != 200) {
          throw LocalSourceHttpException(
            message: 'Internet Archive 视频搜索 HTTP 状态异常',
            uri: uri,
            statusCode: response.statusCode,
            bodyPreview: bodyPreview(response.body),
            retryAfterSeconds: parseRetryAfterSeconds(response),
          );
        }

        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final docs =
            (data['response'] as Map<String, dynamic>?)?['docs'] as List? ?? [];
        final rawCount = docs.length;

        final results = docs
            .whereType<Map>()
            .map((doc) => Map<String, dynamic>.from(doc))
            .map((doc) {
              final identifier = '${doc['identifier'] ?? ''}'.trim();
              if (identifier.isEmpty) {
                return null;
              }

              return SearchResult(
                id: 'internet-archive-video-$identifier',
                title: '${doc['title'] ?? identifier}'.trim(),
                source: 'internet_archive_video',
                mediaType: MediaType.video,
                mediaSubtype: MediaSubtype.video,
                thumbnailUrl: 'https://archive.org/services/img/$identifier',
                durationSeconds: 0,
                playUrl: 'https://archive.org/embed/$identifier',
                playbackKind: SearchPlaybackKind.embeddedWeb,
                isPlayable: true,
                availability: ResultAvailability.available,
                sourceTier: SourceTier.officialApi,
                canonicalUrl: 'https://archive.org/details/$identifier',
                artistOrAuthor: '${doc['creator'] ?? ''}'.trim(),
                albumOrSeries: 'Internet Archive',
                description: _normalizeDescription(doc['description']),
              );
            })
            .whereType<SearchResult>()
            .toList(growable: false);

        _rateLimitState.onSuccess();
        reportLocalSourceDebug(
          source: 'internet_archive_video',
          location: 'internet_archive_video_local_source.dart:search',
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
          source: 'internet_archive_video',
          location: 'internet_archive_video_local_source.dart:search',
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
            source: 'internet_archive_video',
            location: 'internet_archive_video_local_source.dart:search',
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
          source: 'internet_archive_video',
          location: 'internet_archive_video_local_source.dart:search',
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
      source: 'internet_archive_video',
      location: 'internet_archive_video_local_source.dart:search',
      msg: 'search degraded to empty result',
      data: {
        'query': query,
        'error': lastError?.toString(),
      },
    );
    return [];
  }

  static String _buildQuery(String query) {
    final escaped = query.replaceAll('"', r'\"').trim();
    return 'mediatype:movies AND (title:($escaped) OR description:($escaped))';
  }

  static String _normalizeDescription(Object? value) {
    if (value is List) {
      return value
          .map((item) => '$item'.trim())
          .where((item) => item.isNotEmpty)
          .join(' ');
    }
    return '$value'.trim();
  }
}
