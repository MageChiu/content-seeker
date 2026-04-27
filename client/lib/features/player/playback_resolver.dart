import 'package:flutter/foundation.dart';

import '../../models/media_playback.dart';
import '../../models/play_request.dart';
import '../../native_bridge/seeker_native.dart';

class PlaybackResolver {
  const PlaybackResolver();

  Future<PlaybackDescriptor> resolve(PlayRequest request) async {
    final playUrl = request.url.trim();
    if (playUrl.isEmpty) {
      throw StateError('当前内容缺少统一播放地址，无法站内播放');
    }

    final lowerUrl = playUrl.toLowerCase();

    // 1. 已知直接流格式（m3u8/mp4/webm/mp3 等）→ 原生播放
    if (_isNativeStreamUrl(lowerUrl)) {
      return PlaybackDescriptor(
        kind: PlaybackKind.nativeStream,
        primaryUrl: playUrl,
        fallbackUrl: playUrl,
        title: request.title,
        displayLabel: '原生流播放',
        mimeType: _guessMimeType(lowerUrl, request.mediaType),
      );
    }

    // 2. 使用 C++ 原生提取器（Bilibili + YouTube 统一处理）
    final nativeResult = await _tryNativeExtract(playUrl, request);
    if (nativeResult != null) {
      return nativeResult;
    }

    // 3. 直接尝试用 media_kit (libmpv) 加载任意 URL
    //    参考 aiplayer：mpv 底层支持 HTTP/HTTPS/HLS/RTMP/RTSP，
    //    并且如果用户装了 yt-dlp，mpv 会自动调用来解析网站 URL
    if (_isNetworkUrl(playUrl)) {
      return PlaybackDescriptor(
        kind: PlaybackKind.nativeStream,
        primaryUrl: playUrl,
        fallbackUrl: playUrl,
        title: request.title,
        displayLabel: 'mpv 直接加载',
      );
    }

    // 4. 兜底：外部浏览器
    return PlaybackDescriptor(
      kind: PlaybackKind.external,
      primaryUrl: playUrl,
      fallbackUrl: playUrl,
      title: request.title,
      displayLabel: '浏览器兜底',
    );
  }

  /// 使用 C++ 原生提取器尝试解析流地址
  Future<PlaybackDescriptor?> _tryNativeExtract(
      String url, PlayRequest request) async {
    final seeker = SeekerNative.instance;
    if (!seeker.isInitialized) return null;

    try {
      final extracted = await seeker.extractStream(url).timeout(
        const Duration(seconds: 10),
      );
      if (extracted.url.isEmpty) return null;

      debugPrint('[libseeker] 原生提取成功: ${extracted.quality}');
      return PlaybackDescriptor(
        kind: PlaybackKind.nativeStream,
        primaryUrl: extracted.url,
        secondaryUrl: extracted.audioUrl,
        fallbackUrl: request.url,
        title: extracted.title.isNotEmpty ? extracted.title : request.title,
        displayLabel: '原生提取 (${extracted.quality})',
        mimeType: extracted.mimeType.isNotEmpty ? extracted.mimeType : null,
        headers: extracted.headers,
      );
    } catch (e) {
      debugPrint('[libseeker] 原生提取失败: $e');
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

  bool _isNetworkUrl(String url) {
    return url.startsWith('http://') ||
        url.startsWith('https://') ||
        url.startsWith('rtmp://') ||
        url.startsWith('rtsp://') ||
        url.startsWith('rtp://');
  }

  String? _guessMimeType(String url, PlayMediaType mediaType) {
    if (url.contains('.m3u8')) return 'application/x-mpegURL';
    if (url.contains('.mp4')) return 'video/mp4';
    if (url.contains('.webm')) {
      return mediaType == PlayMediaType.audio ? 'audio/webm' : 'video/webm';
    }
    if (url.contains('.mp3')) return 'audio/mpeg';
    if (url.contains('.m4a')) return 'audio/mp4';
    if (url.contains('.aac')) return 'audio/aac';
    if (url.contains('.wav')) return 'audio/wav';
    return null;
  }
}
