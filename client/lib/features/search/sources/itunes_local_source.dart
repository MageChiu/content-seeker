import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/search_source.dart';
import '../../../models/search_result.dart';

class ItunesLocalSource implements SearchSource {
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
      final uri = Uri.https('itunes.apple.com', '/search', {
        'term': query,
        'entity': 'song',
        'media': 'music',
        'limit': '${limit.clamp(1, 50)}',
        'country': 'CN',
      });
      final response = await http.get(
        uri,
        headers: const {
          'User-Agent':
              'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36',
        },
      );
      if (response.statusCode != 200) {
        return [];
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final items = data['results'] as List? ?? [];

      return items
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .map((item) {
            final previewUrl = '${item['previewUrl'] ?? ''}'.trim();
            final trackId = item['trackId'];
            if (previewUrl.isEmpty || trackId == null) {
              return null;
            }

            final trackName = '${item['trackName'] ?? ''}'.trim();
            final artistName = '${item['artistName'] ?? ''}'.trim();
            final collectionName = '${item['collectionName'] ?? ''}'.trim();

            return SearchResult(
              id: '$trackId',
              title: _buildTitle(trackName, artistName),
              source: 'itunes',
              mediaType: MediaType.audio,
              mediaSubtype: MediaSubtype.musicTrack,
              thumbnailUrl: '${item['artworkUrl100'] ?? ''}'.trim(),
              durationSeconds: 30,
              playUrl: previewUrl,
              playbackKind: SearchPlaybackKind.nativeStream,
              isPlayable: true,
              availability: ResultAvailability.preview,
              sourceTier: SourceTier.officialApi,
              canonicalUrl:
                  '${item['trackViewUrl'] ?? item['collectionViewUrl'] ?? previewUrl}'
                      .trim(),
              artistOrAuthor: artistName,
              albumOrSeries: collectionName,
              description: [
                if (artistName.isNotEmpty) artistName,
                if (collectionName.isNotEmpty) collectionName,
              ].join(' / '),
            );
          })
          .whereType<SearchResult>()
          .toList(growable: false);
    } catch (_) {
      return [];
    }
  }

  static String _buildTitle(String trackName, String artistName) {
    if (trackName.isNotEmpty && artistName.isNotEmpty) {
      return '$trackName - $artistName';
    }
    return trackName.isNotEmpty ? trackName : artistName;
  }
}
