import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/search_source.dart';
import '../../../models/search_result.dart';

class JamendoLocalSource implements SearchSource {
  final String clientId;

  JamendoLocalSource({required this.clientId});

  @override
  String get name => 'jamendo_local';

  @override
  bool get isConfigured => clientId.trim().isNotEmpty;

  @override
  Future<List<SearchResult>> search(
    String query, {
    int page = 1,
    int limit = 20,
  }) async {
    if (!isConfigured) {
      return [];
    }

    try {
      final uri = Uri.https('api.jamendo.com', '/v3.0/tracks', {
        'client_id': clientId,
        'format': 'json',
        'limit': '${limit.clamp(1, 50)}',
        'audioformat': 'mp31',
        'namesearch': query,
      });
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        return [];
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final items = data['results'] as List? ?? [];

      return items
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .map((item) {
            final trackId = item['id'];
            if (trackId == null) {
              return null;
            }

            final audioUrl = '${item['audio'] ?? ''}'.trim();
            final shareUrl = '${item['shareurl'] ?? ''}'.trim();
            final title = '${item['name'] ?? ''}'.trim();
            final artistName = '${item['artist_name'] ?? ''}'.trim();
            final albumName = '${item['album_name'] ?? ''}'.trim();

            return SearchResult(
              id: 'jamendo-$trackId',
              title: artistName.isNotEmpty ? '$title - $artistName' : title,
              source: 'jamendo',
              mediaType: MediaType.audio,
              mediaSubtype: MediaSubtype.musicTrack,
              thumbnailUrl: '${item['image'] ?? ''}'.trim(),
              durationSeconds: _readInt(item['duration']),
              playUrl: audioUrl.isNotEmpty ? audioUrl : shareUrl,
              playbackKind: audioUrl.isNotEmpty
                  ? SearchPlaybackKind.nativeStream
                  : SearchPlaybackKind.externalOpen,
              isPlayable: audioUrl.isNotEmpty,
              availability: audioUrl.isNotEmpty
                  ? ResultAvailability.available
                  : ResultAvailability.indexedOnly,
              sourceTier: SourceTier.officialApi,
              canonicalUrl:
                  shareUrl.isNotEmpty ? shareUrl : audioUrl,
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
    } catch (_) {
      return [];
    }
  }

  static int _readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse('$value') ?? 0;
  }
}
