import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/search_source.dart';
import '../../../models/search_result.dart';
import 'media_search_query_helper.dart';

class ItunesLocalSource implements SearchSource {
  static const List<String> _countries = ['CN', 'US', 'GB'];

  @override
  String get name => 'itunes_local';

  @override
  bool get isConfigured => true;

  @override
  Future<List<SearchResult>> search(
    String query, {
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final deduped = <String, SearchResult>{};
      for (final effectiveQuery in buildMediaSearchQueries(query)) {
        for (final country in _countries) {
          final uri = Uri.https('itunes.apple.com', '/search', {
            'term': effectiveQuery,
            'entity': 'song',
            'media': 'music',
            'attribute': 'songTerm',
            'limit': '${limit.clamp(1, 50)}',
            'country': country,
          });
          final response = await http.get(
            uri,
            headers: const {
              'User-Agent':
                  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36',
            },
          );
          if (response.statusCode != 200) {
            continue;
          }

          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final items = data['results'] as List? ?? [];
          final results = items
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .map(_mapItem)
              .whereType<SearchResult>()
              .toList(growable: false);
          for (final result in results) {
            deduped['${result.id}_${result.artistOrAuthor.toLowerCase()}'] =
                result;
          }
          if (deduped.length >= limit) {
            return deduped.values.take(limit).toList(growable: false);
          }
        }
      }
      return deduped.values.take(limit).toList(growable: false);
    } catch (_) {
      return [];
    }
  }

  SearchResult? _mapItem(Map<String, dynamic> item) {
    final trackId = item['trackId'];
    if (trackId == null) {
      return null;
    }

    final previewUrl = '${item['previewUrl'] ?? ''}'.trim();
    final trackViewUrl = '${item['trackViewUrl'] ?? ''}'.trim();
    final collectionViewUrl = '${item['collectionViewUrl'] ?? ''}'.trim();
    final trackName = '${item['trackName'] ?? ''}'.trim();
    final artistName = '${item['artistName'] ?? ''}'.trim();
    final collectionName = '${item['collectionName'] ?? ''}'.trim();
    final description = '${item['primaryGenreName'] ?? ''}'.trim();
    final canonicalUrl = trackViewUrl.isNotEmpty
        ? trackViewUrl
        : (collectionViewUrl.isNotEmpty ? collectionViewUrl : previewUrl);
    if (trackName.isEmpty && artistName.isEmpty) {
      return null;
    }

    return SearchResult(
      id: '$trackId',
      title: _buildTitle(trackName, artistName),
      source: 'itunes',
      mediaType: MediaType.audio,
      mediaSubtype: MediaSubtype.musicTrack,
      thumbnailUrl: _upgradeArtwork('${item['artworkUrl100'] ?? ''}'.trim()),
      durationSeconds: _readDuration(item['trackTimeMillis']),
      playUrl: previewUrl.isNotEmpty ? previewUrl : canonicalUrl,
      playbackKind: previewUrl.isNotEmpty
          ? SearchPlaybackKind.nativeStream
          : SearchPlaybackKind.externalOpen,
      isPlayable: previewUrl.isNotEmpty,
      availability: previewUrl.isNotEmpty
          ? ResultAvailability.preview
          : ResultAvailability.indexedOnly,
      sourceTier: SourceTier.officialApi,
      canonicalUrl: canonicalUrl,
      artistOrAuthor: artistName,
      albumOrSeries: collectionName,
      description: [
        if (artistName.isNotEmpty) artistName,
        if (collectionName.isNotEmpty) collectionName,
        if (description.isNotEmpty) description,
      ].join(' / '),
    );
  }

  static String _buildTitle(String trackName, String artistName) {
    if (trackName.isNotEmpty && artistName.isNotEmpty) {
      return '$trackName - $artistName';
    }
    return trackName.isNotEmpty ? trackName : artistName;
  }

  static String _upgradeArtwork(String value) {
    if (value.isEmpty) {
      return value;
    }
    return value.replaceAll('100x100bb', '512x512bb');
  }

  static int _readDuration(Object? value) {
    if (value is int) {
      return (value / 1000).round();
    }
    if (value is num) {
      return (value / 1000).round();
    }
    return 0;
  }
}
