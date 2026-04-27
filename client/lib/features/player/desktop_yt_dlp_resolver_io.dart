import 'dart:convert';
import 'dart:io';

import '../../models/media_playback.dart';
import '../../models/search_result.dart';
import 'desktop_yt_dlp_resolver_interface.dart';

class _DesktopYtDlpResolverIO implements DesktopYtDlpResolver {
  static const List<String> _executables = ['yt-dlp', 'youtube-dl'];

  @override
  Future<PlaybackDescriptor?> resolve(SearchResult result) async {
    if (!_isSupportedPlatform || !_supportsSource(result)) {
      return null;
    }

    for (final executable in _executables) {
      final directInfo = await _runDumpSingleJson(
        executable: executable,
        url: result.playUrl,
      );
      final directResolved = _buildDescriptor(result, directInfo);
      if (directResolved != null) {
        return directResolved;
      }

      if (result.source == 'bilibili') {
        for (final browser in _cookieBrowsers) {
          final cookieInfo = await _runDumpSingleJson(
            executable: executable,
            url: result.playUrl,
            browser: browser,
          );
          final cookieResolved = _buildDescriptor(result, cookieInfo);
          if (cookieResolved != null) {
            return cookieResolved;
          }
        }
      }
    }

    return null;
  }

  bool get _isSupportedPlatform =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  bool _supportsSource(SearchResult result) {
    return result.playUrl.trim().isNotEmpty &&
        (result.source == 'youtube' || result.source == 'bilibili');
  }

  List<String> get _cookieBrowsers {
    if (Platform.isMacOS) {
      return const ['chrome', 'firefox', 'safari'];
    }
    if (Platform.isWindows) {
      return const ['chrome', 'edge', 'firefox'];
    }
    return const ['chrome', 'chromium', 'firefox'];
  }

  Future<Map<String, dynamic>?> _runDumpSingleJson({
    required String executable,
    required String url,
    String? browser,
  }) async {
    try {
      final arguments = <String>[
        '--no-playlist',
        '--dump-single-json',
        if (browser != null) ...[
          '--cookies-from-browser',
          browser,
        ],
        url,
      ];
      final result = await Process.run(executable, arguments);
      if (result.exitCode != 0) {
        return null;
      }

      final decoded = jsonDecode(result.stdout as String);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  PlaybackDescriptor? _buildDescriptor(
    SearchResult result,
    Map<String, dynamic>? info,
  ) {
    if (info == null) return null;

    final format = result.mediaType == MediaType.audio
        ? _pickAudioFormat(info)
        : _pickVideoFormat(info);
    if (format == null) {
      return null;
    }

    final url = format['url'];
    if (url is! String || url.isEmpty) {
      return null;
    }

    return PlaybackDescriptor(
      kind: PlaybackKind.nativeStream,
      primaryUrl: url,
      fallbackUrl: result.playUrl,
      title: (info['title'] as String?)?.trim().isNotEmpty == true
          ? info['title'] as String
          : result.title,
      displayLabel: '桌面本地解析',
      mimeType: _guessMimeType(format),
      headers: _readHeaders(info, format),
    );
  }

  Map<String, dynamic>? _pickVideoFormat(Map<String, dynamic> info) {
    final formats = (info['formats'] as List?) ?? const [];
    final candidates = <Map<String, dynamic>>[];

    for (final raw in formats) {
      if (raw is! Map) continue;
      final format = Map<String, dynamic>.from(raw);
      final url = format['url'];
      final vcodec = format['vcodec'];
      final acodec = format['acodec'];
      final protocol = '${format['protocol'] ?? ''}'.toLowerCase();
      if (url is! String || url.isEmpty) continue;
      if (vcodec == null || vcodec == 'none') continue;
      if (acodec == null || acodec == 'none') continue;
      if (!_isPlayableProtocol(protocol)) continue;
      candidates.add(format);
    }

    if (candidates.isEmpty) {
      return null;
    }

    candidates.sort((a, b) => _scoreFormat(a).compareTo(_scoreFormat(b)));
    return candidates.last;
  }

  Map<String, dynamic>? _pickAudioFormat(Map<String, dynamic> info) {
    final formats = (info['formats'] as List?) ?? const [];
    final candidates = <Map<String, dynamic>>[];

    for (final raw in formats) {
      if (raw is! Map) continue;
      final format = Map<String, dynamic>.from(raw);
      final url = format['url'];
      final acodec = format['acodec'];
      final protocol = '${format['protocol'] ?? ''}'.toLowerCase();
      if (url is! String || url.isEmpty) continue;
      if (acodec == null || acodec == 'none') continue;
      if (!_isPlayableProtocol(protocol)) continue;
      candidates.add(format);
    }

    if (candidates.isEmpty) {
      return null;
    }

    candidates.sort((a, b) {
      final abrA = (a['abr'] as num?)?.toDouble() ?? 0;
      final abrB = (b['abr'] as num?)?.toDouble() ?? 0;
      return abrA.compareTo(abrB);
    });
    return candidates.last;
  }

  bool _isPlayableProtocol(String protocol) {
    return protocol.startsWith('http') ||
        protocol.contains('m3u8') ||
        protocol.contains('https');
  }

  double _scoreFormat(Map<String, dynamic> format) {
    final height = (format['height'] as num?)?.toDouble() ?? 0;
    final bitrate = (format['tbr'] as num?)?.toDouble() ?? 0;
    final protocol = '${format['protocol'] ?? ''}'.toLowerCase();
    final protocolScore = protocol.contains('m3u8') ? 1000 : 500;
    return (height * 100000) + bitrate + protocolScore;
  }

  Map<String, String> _readHeaders(
    Map<String, dynamic> info,
    Map<String, dynamic> format,
  ) {
    final raw = (format['http_headers'] as Map?) ?? (info['http_headers'] as Map?);
    if (raw == null) return const {};
    return raw.map((key, value) => MapEntry('$key', '$value'));
  }

  String? _guessMimeType(Map<String, dynamic> format) {
    final ext = '${format['ext'] ?? ''}'.toLowerCase();
    final protocol = '${format['protocol'] ?? ''}'.toLowerCase();
    if (protocol.contains('m3u8')) return 'application/x-mpegURL';
    if (ext == 'mp4') return 'video/mp4';
    if (ext == 'webm') return 'video/webm';
    if (ext == 'm4a') return 'audio/mp4';
    if (ext == 'mp3') return 'audio/mpeg';
    return null;
  }
}

DesktopYtDlpResolver createDesktopYtDlpResolverImpl() =>
    _DesktopYtDlpResolverIO();
