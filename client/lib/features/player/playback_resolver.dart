import '../../models/media_playback.dart';
import '../../models/search_result.dart';
import 'bilibili_playback_resolver.dart';
import 'desktop_yt_dlp_resolver.dart';

class PlaybackResolver {
  const PlaybackResolver();

  static const BilibiliPlaybackResolver _bilibiliPlaybackResolver =
      BilibiliPlaybackResolver();
  static final _desktopYtDlpResolver = createDesktopYtDlpResolver();

  Future<PlaybackDescriptor> resolve(SearchResult result) async {
    final playUrl = result.playUrl.trim();
    if (playUrl.isEmpty) {
      throw StateError('当前内容缺少统一播放地址，无法站内播放');
    }

    final lowerUrl = playUrl.toLowerCase();
    final playUri = Uri.tryParse(playUrl);
    final embeddedUrl = _buildEmbeddedUrl(result, playUrl, playUri);

    if (_isNativeStreamUrl(lowerUrl)) {
      return PlaybackDescriptor(
        kind: PlaybackKind.nativeStream,
        primaryUrl: playUrl,
        fallbackUrl: playUrl,
        title: result.title,
        displayLabel: '原生流播放',
        mimeType: _guessMimeType(lowerUrl, result.mediaType),
      );
    }

    final bilibiliResolved = await _bilibiliPlaybackResolver.resolve(result);
    if (bilibiliResolved != null) {
      return bilibiliResolved;
    }

    final localDesktopResolved = await _desktopYtDlpResolver.resolve(result);
    if (localDesktopResolved != null) {
      return localDesktopResolved;
    }

    if (embeddedUrl != null) {
      return PlaybackDescriptor(
        kind: PlaybackKind.embeddedWeb,
        primaryUrl: embeddedUrl,
        fallbackUrl: playUrl,
        title: result.title,
        displayLabel: '站内网页播放',
      );
    }

    return PlaybackDescriptor(
      kind: PlaybackKind.external,
      primaryUrl: playUrl,
      fallbackUrl: playUrl,
      title: result.title,
      displayLabel: '浏览器兜底',
    );
  }

  String? _buildEmbeddedUrl(
    SearchResult result,
    String playUrl,
    Uri? playUri,
  ) {
    switch (_resolveSourceKey(result, playUri)) {
      case 'youtube':
        final videoId = _extractYouTubeId(result.id, playUrl);
        if (videoId == null || videoId.isEmpty) return null;
        return Uri.https('www.youtube.com', '/embed/$videoId', {
          'autoplay': '1',
          'playsinline': '1',
          'rel': '0',
        }).toString();
      case 'bilibili':
        final bvid = _extractBilibiliId(result.id, playUrl);
        if (bvid == null || bvid.isEmpty) return null;
        return Uri.https('player.bilibili.com', '/player.html', {
          'bvid': bvid,
          'page': '1',
          'autoplay': '1',
          'high_quality': '1',
        }).toString();
      default:
        if (_supportsEmbeddedWeb(playUri)) {
          return playUrl;
        }
        return null;
    }
  }

  bool _isNativeStreamUrl(String url) {
    return url.contains('.m3u8') ||
        url.contains('.mp4') ||
        url.contains('.webm') ||
        url.contains('.mp3') ||
        url.contains('.m4a') ||
        url.contains('.aac') ||
        url.contains('.wav');
  }

  bool _supportsEmbeddedWeb(Uri? uri) {
    if (uri == null) return false;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      return false;
    }

    final host = uri.host.toLowerCase();
    return host.contains('youtube.com') ||
        host.contains('youtu.be') ||
        host.contains('player.bilibili.com') ||
        host.contains('bilibili.com');
  }

  String? _guessMimeType(String url, MediaType mediaType) {
    if (url.contains('.m3u8')) return 'application/x-mpegURL';
    if (url.contains('.mp4')) return 'video/mp4';
    if (url.contains('.webm')) {
      return mediaType == MediaType.audio ? 'audio/webm' : 'video/webm';
    }
    if (url.contains('.mp3')) return 'audio/mpeg';
    if (url.contains('.m4a')) return 'audio/mp4';
    if (url.contains('.aac')) return 'audio/aac';
    if (url.contains('.wav')) return 'audio/wav';
    return null;
  }

  String? _extractYouTubeId(String resultId, String playUrl) {
    if (resultId.isNotEmpty) return resultId;

    final uri = Uri.tryParse(playUrl);
    if (uri == null) return null;
    if (uri.host.contains('youtu.be')) {
      return uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
    }
    return uri.queryParameters['v'];
  }

  String? _extractBilibiliId(String resultId, String playUrl) {
    if (resultId.isNotEmpty) return resultId;

    final uri = Uri.tryParse(playUrl);
    if (uri == null) return null;
    final segments = uri.pathSegments;
    if (segments.length >= 2 && segments.first == 'video') {
      return segments[1];
    }
    return null;
  }

  String _resolveSourceKey(SearchResult result, Uri? playUri) {
    if (result.sourceKey.isNotEmpty) {
      return result.sourceKey;
    }

    final host = playUri?.host.toLowerCase() ?? '';
    if (host.contains('youtube.com') || host.contains('youtu.be')) {
      return 'youtube';
    }
    if (host.contains('bilibili.com')) {
      return 'bilibili';
    }
    return '';
  }
}
