// 通道 1: 用户自有 YouTube API Key，客户端直调
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/search_source.dart';
import '../../../models/search_result.dart';

class YouTubeLocalSource implements SearchSource {
  final String apiKey;

  YouTubeLocalSource({required this.apiKey});

  @override
  String get name => 'youtube_local';

  @override
  bool get isConfigured => apiKey.isNotEmpty;

  @override
  Future<List<SearchResult>> search(String query,
      {int page = 1, int limit = 20}) async {
    final uri = Uri.https('www.googleapis.com', '/youtube/v3/search', {
      'part': 'snippet',
      'q': query,
      'type': 'video',
      'maxResults': '$limit',
      'key': apiKey,
    });

    final response = await http.get(uri);
    if (response.statusCode != 200) return [];

    final data = jsonDecode(response.body);
    final items = data['items'] as List? ?? [];

    return items.map((item) {
      final snippet = item['snippet'] ?? {};
      final videoId = item['id']?['videoId'] ?? '';
      return SearchResult(
        id: videoId,
        title: snippet['title'] ?? '',
        source: 'youtube',
        mediaType: MediaType.video,
        mediaSubtype: MediaSubtype.video,
        thumbnailUrl:
            snippet['thumbnails']?['high']?['url'] ?? '',
        durationSeconds: 0,
        playUrl: 'https://www.youtube.com/watch?v=$videoId',
        playbackKind: SearchPlaybackKind.externalOpen,
        isPlayable: false,
        availability: ResultAvailability.indexedOnly,
        sourceTier: SourceTier.officialApi,
        canonicalUrl: 'https://www.youtube.com/watch?v=$videoId',
        artistOrAuthor: snippet['channelTitle'] ?? '',
        albumOrSeries: '',
        description: snippet['description'] ?? '',
      );
    }).toList();
  }
}
