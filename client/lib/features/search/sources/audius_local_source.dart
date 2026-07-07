import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/search_source.dart';
import '../../../models/search_result.dart';
import 'local_source_debug.dart';
import 'media_search_query_helper.dart';

class AudiusLocalSource implements SearchSource {
  static String? _cachedHost;

  final String apiKey;

  AudiusLocalSource({this.apiKey = ''});

  @override
  String get name => 'audius_local';

  @override
  bool get isConfigured => true;

  @override
  Future<List<SearchResult>> search(
    String query, {
    int page = 1,
    int limit = 20,
  }) async {
    final host = await _resolveHost();
    if (host == null || host.isEmpty) {
      return [];
    }

    final deduped = <String, SearchResult>{};
    for (final effectiveQuery in buildMediaSearchQueries(query, maxVariants: 4)) {
      final uri = Uri.parse('$host/v1/tracks/search').replace(
        queryParameters: {
          'query': effectiveQuery,
          'limit': '${limit.clamp(1, 30)}',
          'offset': '${((page - 1).clamp(0, 999)) * limit}',
          'sort_method': 'relevant',
          'app_name': 'content_seeker',
          if (apiKey.trim().isNotEmpty) 'api_key': apiKey.trim(),
        },
      );

      try {
        reportLocalSourceDebug(
          source: 'audius',
          location: 'audius_local_source.dart:search',
          msg: 'request start',
          data: {
            'query': query,
            'effectiveQuery': effectiveQuery,
            'uri': uri.toString(),
          },
        );
        final response = await http.get(uri).timeout(const Duration(seconds: 12));
        if (response.statusCode != 200) {
          reportLocalSourceDebug(
            source: 'audius',
            location: 'audius_local_source.dart:search',
            msg: 'request failed',
            data: {
              'statusCode': response.statusCode,
              'bodyPreview': bodyPreview(response.body),
            },
          );
          continue;
        }

        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final items = data['data'] as List? ?? [];
        final results = items
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .map((item) => _mapTrack(host, item))
            .whereType<SearchResult>()
            .toList(growable: false);
        for (final result in results) {
          deduped[result.id] = result;
        }
        reportLocalSourceDebug(
          source: 'audius',
          location: 'audius_local_source.dart:search',
          msg: 'response parsed',
          data: {
            'effectiveQuery': effectiveQuery,
            'rawItemCount': items.length,
            'resultCount': results.length,
          },
        );
        if (deduped.isNotEmpty) {
          return deduped.values.take(limit).toList(growable: false);
        }
      } catch (error) {
        reportLocalSourceDebug(
          source: 'audius',
          location: 'audius_local_source.dart:search',
          msg: 'request exception',
          data: {
            'query': query,
            'effectiveQuery': effectiveQuery,
            'error': error.toString(),
          },
        );
      }
    }
    return deduped.values.take(limit).toList(growable: false);
  }

  SearchResult? _mapTrack(String host, Map<String, dynamic> item) {
    final trackId = '${item['id'] ?? ''}'.trim();
    if (trackId.isEmpty) {
      return null;
    }

    final user = Map<String, dynamic>.from((item['user'] as Map?) ?? const {});
    final artistName = '${user['name'] ?? user['handle'] ?? ''}'.trim();
    final title = '${item['title'] ?? ''}'.trim();
    final artwork = Map<String, dynamic>.from(
      (item['artwork'] as Map?) ?? const {},
    );
    final permalink = _normalizePermalink('${item['permalink'] ?? ''}'.trim());
    final streamUrl = Uri.parse('$host/v1/tracks/$trackId/stream').replace(
      queryParameters: {
        'app_name': 'content_seeker',
        if (apiKey.trim().isNotEmpty) 'api_key': apiKey.trim(),
      },
    );
    final isStreamable = item['is_streamable'] != false;
    final genre = '${item['genre'] ?? ''}'.trim();
    final tags = '${item['tags'] ?? ''}'.trim();

    return SearchResult(
      id: 'audius-$trackId',
      title: artistName.isNotEmpty ? '$title - $artistName' : title,
      source: 'audius',
      mediaType: MediaType.audio,
      mediaSubtype: MediaSubtype.musicTrack,
      thumbnailUrl: '${artwork['480x480'] ?? artwork['1000x1000'] ?? artwork['150x150'] ?? ''}'
          .trim(),
      durationSeconds: _readInt(item['duration']),
      playUrl: isStreamable ? streamUrl.toString() : permalink,
      playbackKind: isStreamable
          ? SearchPlaybackKind.nativeStream
          : SearchPlaybackKind.externalOpen,
      isPlayable: isStreamable,
      availability: isStreamable
          ? ResultAvailability.available
          : ResultAvailability.indexedOnly,
      sourceTier: SourceTier.publicApi,
      canonicalUrl: permalink,
      artistOrAuthor: artistName,
      albumOrSeries: genre,
      description: [
        if (artistName.isNotEmpty) artistName,
        if (genre.isNotEmpty) genre,
        if (tags.isNotEmpty) tags,
      ].join(' / '),
      supportsDownload: item['is_downloadable'] == true,
    );
  }

  Future<String?> _resolveHost() async {
    if (_cachedHost != null && _cachedHost!.isNotEmpty) {
      return _cachedHost;
    }

    try {
      final response = await http
          .get(Uri.parse('https://api.audius.co'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        return null;
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final hosts = (data['data'] as List? ?? const [])
          .map((item) => '$item'.trim())
          .where((item) => item.startsWith('https://'))
          .toList(growable: false);
      if (hosts.isEmpty) {
        return null;
      }
      _cachedHost = hosts.first;
      return _cachedHost;
    } catch (_) {
      return null;
    }
  }

  static String _normalizePermalink(String value) {
    if (value.isEmpty) {
      return value;
    }
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    return value.startsWith('/') ? 'https://audius.co$value' : 'https://audius.co/$value';
  }

  static int _readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse('$value') ?? 0;
  }
}
