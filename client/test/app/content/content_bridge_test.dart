import 'package:flutter_test/flutter_test.dart';

import 'package:content_seeker/app/content/content_bridge.dart';
import 'package:content_seeker/app/content/content_request.dart';
import 'package:content_seeker/domain/download/download_request.dart';
import 'package:content_seeker/models/search_result.dart';

void main() {
  group('ContentBridge', () {
    test('bridges search result to content request with normalized fields', () {
      final result = SearchResult(
        id: '  audio-42  ',
        title: 'Rain/Harbor:Live?',
        source: ' YouTube ',
        mediaType: MediaType.audio,
        thumbnailUrl: 'https://example.com/thumb.jpg',
        durationSeconds: 245,
        playUrl: ' https://cdn.example.com/media/track.MP3?from=search ',
        playbackKind: SearchPlaybackKind.embeddedWeb,
        availability: ResultAvailability.preview,
        sourceTier: SourceTier.officialApi,
        canonicalUrl: ' https://example.com/articles/rain-harbor ',
        description: 'sample description',
      );

      final request = result.toContentRequest(intent: ContentIntent.download);

      expect(request.intent, ContentIntent.download);
      expect(request.contentId, 'audio-42');
      expect(request.sourceId, 'youtube');
      expect(request.mediaType, ContentMediaType.audio);
      expect(
        request.primaryUri,
        Uri.parse('https://cdn.example.com/media/track.MP3?from=search'),
      );
      expect(
        request.fallbackUri,
        Uri.parse('https://example.com/articles/rain-harbor'),
      );
      expect(request.sourceLabel, 'YouTube');
      expect(request.filename, 'Rain_Harbor_Live_.mp3');
      expect(request.attributes, {
        'playbackKind': 'embeddedWeb',
        'availability': 'preview',
        'sourceTier': 'officialApi',
      });
    });

    test('bridges download request and infers audio media type from filename', () {
      final request = DownloadRequest(
        mediaId: 'ep-7',
        sourceId: ' RSS ',
        url: Uri.parse('https://example.com/audio/episode'),
        filename: 'weekly-roundup.m4a',
        headers: {'Authorization': 'Bearer token'},
      );

      final contentRequest = request.toContentRequest();

      expect(contentRequest.intent, ContentIntent.download);
      expect(contentRequest.contentId, 'ep-7');
      expect(contentRequest.sourceId, 'rss');
      expect(contentRequest.mediaType, ContentMediaType.audio);
      expect(contentRequest.filename, 'weekly-roundup.m4a');
      expect(contentRequest.headers, {'Authorization': 'Bearer token'});
    });

    test('bridges content request back to legacy download request and validates uri', () {
      final contentRequest = ContentRequest(
        intent: ContentIntent.playback,
        contentId: 'vid-9',
        sourceId: 'bilibili',
        title: 'Harbor Story',
        mediaType: ContentMediaType.video,
        primaryUri: Uri.parse('https://example.com/video/watch.mp4'),
        sourceLabel: 'Bilibili',
        thumbnailUrl: 'https://example.com/cover.png',
        durationSeconds: 120,
        description: 'demo',
        headers: {'Referer': 'https://example.com'},
      );

      final downloadRequest = contentRequest.toLegacyDownloadRequest();

      expect(contentRequest.hasPrimaryUri, isTrue);
      expect(contentRequest.stableId, 'bilibili-vid-9');
      expect(downloadRequest.filename, 'Harbor Story.mp4');
      expect(downloadRequest.headers, {'Referer': 'https://example.com'});

      const noUriRequest = ContentRequest(
        intent: ContentIntent.playback,
        contentId: 'vid-10',
        sourceId: 'bilibili',
        title: 'Broken',
      );
      expect(noUriRequest.toLegacyDownloadRequest, throwsStateError);
    });
  });
}
