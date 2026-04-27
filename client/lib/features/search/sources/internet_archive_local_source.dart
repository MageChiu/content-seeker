import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/search_source.dart';
import '../../../models/search_result.dart';
import 'local_source_debug.dart';

class InternetArchiveLocalSource implements SearchSource {
  static const _playableExtensions = [
    '.mp3',
    '.ogg',
    '.opus',
    '.flac',
    '.m4a',
    '.wav',
  ];
  static const int _maxAttempts = 3;
  static final LocalSourceRateLimitState _searchRateLimitState =
      LocalSourceRateLimitState();
  static final LocalSourceRateLimitState _metadataRateLimitState =
      LocalSourceRateLimitState();

  @override
  String get name => 'internet_archive_local';

  @override
  bool get isConfigured => true;

  @override
  Future<List<SearchResult>> search(
    String query, {
    int page = 1,
    int limit = 20,
  }) async {
    if (_searchRateLimitState.isCoolingDown) {
      reportLocalSourceDebug(
        source: 'internet_archive_audio',
        location: 'internet_archive_local_source.dart:search',
        msg: 'skip search during cooldown',
        data: {
          'query': query,
          'remainingMs': _searchRateLimitState.remainingCooldown.inMilliseconds,
        },
      );
      return [];
    }

    Object? lastError;
    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        final uri = Uri.https('archive.org', '/advancedsearch.php', {
          'q': _buildQuery(query),
          'fl[]': 'identifier,title,creator,collection,description',
          'sort[]': 'downloads desc',
          'rows': '${limit.clamp(1, 10)}',
          'page': '$page',
          'output': 'json',
        });
        reportLocalSourceDebug(
          source: 'internet_archive_audio',
          location: 'internet_archive_local_source.dart:search',
          msg: 'search request start',
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
          source: 'internet_archive_audio',
          location: 'internet_archive_local_source.dart:search',
          msg: 'search response received',
          data: {
            'attempt': attempt,
            'statusCode': response.statusCode,
            'bodyPreview': bodyPreview(response.body),
          },
        );

        if (response.statusCode != 200) {
          throw LocalSourceHttpException(
            message: 'Internet Archive 音频搜索 HTTP 状态异常',
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
        final results = await Future.wait(
          docs
              .whereType<Map>()
              .map((doc) => _mapDoc(Map<String, dynamic>.from(doc)))
              .toList(growable: false),
        );
        final filtered = results.whereType<SearchResult>().toList(growable: false);
        _searchRateLimitState.onSuccess();
        reportLocalSourceDebug(
          source: 'internet_archive_audio',
          location: 'internet_archive_local_source.dart:search',
          msg: 'search response parsed',
          data: {
            'attempt': attempt,
            'rawItemCount': rawCount,
            'resultCount': filtered.length,
            'filteredOutCount': rawCount - filtered.length,
          },
        );
        return filtered;
      } catch (error) {
        lastError = error;
        reportLocalSourceDebug(
          source: 'internet_archive_audio',
          location: 'internet_archive_local_source.dart:search',
          msg: 'search request failed',
          data: {
            'query': query,
            'attempt': attempt,
            'error': error.toString(),
          },
        );

        if (isRateLimitedLocalSourceError(error) &&
            error is LocalSourceHttpException) {
          final cooldown = _searchRateLimitState.activateCooldown(
            retryAfterSeconds: error.retryAfterSeconds,
          );
          reportLocalSourceDebug(
            source: 'internet_archive_audio',
            location: 'internet_archive_local_source.dart:search',
            msg: 'search rate limited, cooldown activated',
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
            _searchRateLimitState.isCoolingDown) {
          break;
        }

        final delay = retryDelayForAttempt(
          attempt,
          rateLimited: isRateLimitedLocalSourceError(error),
        );
        reportLocalSourceDebug(
          source: 'internet_archive_audio',
          location: 'internet_archive_local_source.dart:search',
          msg: 'search retry scheduled',
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
      source: 'internet_archive_audio',
      location: 'internet_archive_local_source.dart:search',
      msg: 'search degraded to empty result',
      data: {
        'query': query,
        'error': lastError?.toString(),
      },
    );
    return [];
  }

  Future<SearchResult?> _mapDoc(Map<String, dynamic> doc) async {
    final identifier = '${doc['identifier'] ?? ''}'.trim();
    if (identifier.isEmpty) {
      return null;
    }

    final metadata = await _loadMetadata(identifier);
    final selection = _selectPlayableFile(identifier, metadata);
    final creator = _stringify(doc['creator']);
    final collection = _stringify(doc['collection']);
    final description = _stringify(doc['description']);
    final detailUrl = 'https://archive.org/details/$identifier';

    if (selection.playUrl.isEmpty) {
      reportLocalSourceDebug(
        source: 'internet_archive_audio',
        location: 'internet_archive_local_source.dart:_mapDoc',
        msg: 'metadata degraded to indexed-only result',
        data: {
          'identifier': identifier,
          'hasMetadata': metadata.isNotEmpty,
        },
      );
    }

    return SearchResult(
      id: 'internet-archive-$identifier',
      title: '${doc['title'] ?? identifier}'.trim(),
      source: 'internet_archive',
      mediaType: MediaType.audio,
      mediaSubtype: MediaSubtype.musicTrack,
      thumbnailUrl: 'https://archive.org/services/img/$identifier',
      durationSeconds: selection.durationSeconds,
      playUrl: selection.playUrl.isNotEmpty ? selection.playUrl : detailUrl,
      playbackKind: selection.playUrl.isNotEmpty
          ? SearchPlaybackKind.nativeStream
          : SearchPlaybackKind.externalOpen,
      isPlayable: selection.playUrl.isNotEmpty,
      availability: selection.playUrl.isNotEmpty
          ? ResultAvailability.available
          : ResultAvailability.indexedOnly,
      sourceTier: SourceTier.officialApi,
      canonicalUrl: detailUrl,
      artistOrAuthor: creator,
      albumOrSeries: collection,
      description: description,
    );
  }

  Future<Map<String, dynamic>> _loadMetadata(String identifier) async {
    if (_metadataRateLimitState.isCoolingDown) {
      reportLocalSourceDebug(
        source: 'internet_archive_audio',
        location: 'internet_archive_local_source.dart:_loadMetadata',
        msg: 'skip metadata during cooldown',
        data: {
          'identifier': identifier,
          'remainingMs':
              _metadataRateLimitState.remainingCooldown.inMilliseconds,
        },
      );
      return const {};
    }

    Object? lastError;
    for (var attempt = 1; attempt <= 2; attempt++) {
      final metadataUri = Uri.https('archive.org', '/metadata/$identifier');
      try {
        reportLocalSourceDebug(
          source: 'internet_archive_audio',
          location: 'internet_archive_local_source.dart:_loadMetadata',
          msg: 'metadata request start',
          data: {
            'identifier': identifier,
            'attempt': attempt,
            'uri': metadataUri.toString(),
          },
        );
        final metadataResp = await http.get(metadataUri).timeout(
          const Duration(seconds: 10),
        );
        reportLocalSourceDebug(
          source: 'internet_archive_audio',
          location: 'internet_archive_local_source.dart:_loadMetadata',
          msg: 'metadata response received',
          data: {
            'identifier': identifier,
            'attempt': attempt,
            'statusCode': metadataResp.statusCode,
            'bodyPreview': bodyPreview(metadataResp.body),
          },
        );

        if (metadataResp.statusCode != 200) {
          throw LocalSourceHttpException(
            message: 'Internet Archive 音频 metadata HTTP 状态异常',
            uri: metadataUri,
            statusCode: metadataResp.statusCode,
            bodyPreview: bodyPreview(metadataResp.body),
            retryAfterSeconds: parseRetryAfterSeconds(metadataResp),
          );
        }

        final parsed = jsonDecode(metadataResp.body);
        if (parsed is Map<String, dynamic>) {
          _metadataRateLimitState.onSuccess();
          return parsed;
        }
        reportLocalSourceDebug(
          source: 'internet_archive_audio',
          location: 'internet_archive_local_source.dart:_loadMetadata',
          msg: 'metadata response has unexpected shape',
          data: {
            'identifier': identifier,
            'attempt': attempt,
          },
        );
        return const {};
      } catch (error) {
        lastError = error;
        reportLocalSourceDebug(
          source: 'internet_archive_audio',
          location: 'internet_archive_local_source.dart:_loadMetadata',
          msg: 'metadata request failed',
          data: {
            'identifier': identifier,
            'attempt': attempt,
            'error': error.toString(),
          },
        );

        if (isRateLimitedLocalSourceError(error) &&
            error is LocalSourceHttpException) {
          final cooldown = _metadataRateLimitState.activateCooldown(
            retryAfterSeconds: error.retryAfterSeconds,
          );
          reportLocalSourceDebug(
            source: 'internet_archive_audio',
            location: 'internet_archive_local_source.dart:_loadMetadata',
            msg: 'metadata rate limited, cooldown activated',
            data: {
              'identifier': identifier,
              'attempt': attempt,
              'statusCode': error.statusCode,
              'cooldownMs': cooldown.inMilliseconds,
            },
          );
        }

        if (attempt >= 2 ||
            !isRetryableLocalSourceError(error) ||
            _metadataRateLimitState.isCoolingDown) {
          break;
        }
        await Future<void>.delayed(
          retryDelayForAttempt(
            attempt,
            rateLimited: isRateLimitedLocalSourceError(error),
          ),
        );
      }
    }

    reportLocalSourceDebug(
      source: 'internet_archive_audio',
      location: 'internet_archive_local_source.dart:_loadMetadata',
      msg: 'metadata degraded to empty payload',
      data: {
        'identifier': identifier,
        'error': lastError?.toString(),
      },
    );
    return const {};
  }

  _PlayableSelection _selectPlayableFile(
    String identifier,
    Map<String, dynamic> metadata,
  ) {
    final files = metadata['files'];
    if (files is! List) {
      return const _PlayableSelection('', 0);
    }

    for (final file in files.whereType<Map>()) {
      final item = Map<String, dynamic>.from(file);
      final name = '${item['name'] ?? ''}'.trim();
      if (name.isEmpty || !_looksPlayable(item)) {
        continue;
      }

      return _PlayableSelection(
        'https://archive.org/download/$identifier/${Uri.encodeComponent(name)}',
        _parseDuration(item['length']),
      );
    }
    return const _PlayableSelection('', 0);
  }

  bool _looksPlayable(Map<String, dynamic> item) {
    final name = '${item['name'] ?? ''}'.trim().toLowerCase();
    final format = '${item['format'] ?? ''}'.trim().toLowerCase();
    return _playableExtensions.any(name.endsWith) ||
        format.contains('mp3') ||
        format.contains('ogg') ||
        format.contains('flac') ||
        format.contains('audio');
  }

  static String _buildQuery(String query) {
    final escaped = query.replaceAll('"', r'\"').trim();
    return 'title:("$escaped") AND mediatype:(audio OR etree)';
  }

  static String _stringify(Object? value) {
    if (value is List) {
      return value
          .map((item) => '$item'.trim())
          .where((item) => item.isNotEmpty)
          .join(' / ');
    }
    return '$value'.trim();
  }

  static int _parseDuration(Object? value) {
    final text = '$value'.trim();
    if (text.isEmpty) {
      return 0;
    }
    final parts = text.split(':');
    final numbers = parts.map(double.tryParse).toList(growable: false);
    if (numbers.any((item) => item == null)) {
      return int.tryParse(text) ?? 0;
    }
    if (numbers.length == 3) {
      return (numbers[0]! * 3600 + numbers[1]! * 60 + numbers[2]!).round();
    }
    if (numbers.length == 2) {
      return (numbers[0]! * 60 + numbers[1]!).round();
    }
    return numbers.first!.round();
  }
}

class _PlayableSelection {
  final String playUrl;
  final int durationSeconds;

  const _PlayableSelection(this.playUrl, this.durationSeconds);
}
