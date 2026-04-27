import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../models/media_playback.dart';
import '../../models/search_result.dart';

String _debugShortMediaUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return url;
  final lastSegment =
      uri.pathSegments.isNotEmpty ? uri.pathSegments.last : uri.path;
  return '${uri.scheme}://${uri.host}/$lastSegment';
}

// #region debug-point shared:resolver-reporter
Future<void> _reportResolverDebugEvent({
  required String hypothesisId,
  required String location,
  required String message,
  Map<String, Object?> data = const {},
}) async {
  try {
    await http.post(
      Uri.parse('http://127.0.0.1:7777/event'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'sessionId': 'ios-audio-playback',
        'runId': 'pre-fix',
        'hypothesisId': hypothesisId,
        'location': location,
        'msg': '[DEBUG] $message',
        'data': data,
        'ts': DateTime.now().millisecondsSinceEpoch,
      }),
    );
  } catch (_) {}
}
// #endregion

class BilibiliPlaybackResolver {
  static const _userAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/123.0.0.0 Safari/537.36';

  const BilibiliPlaybackResolver();

  Future<PlaybackDescriptor?> resolve(SearchResult result) async {
    if (kIsWeb || result.source != 'bilibili' || result.id.trim().isEmpty) {
      return null;
    }

    try {
      final preferDirectMp4OnIos = defaultTargetPlatform == TargetPlatform.iOS;
      final viewData = await _fetchView(result.id);
      final cid = viewData['cid'];
      if (cid is! num) {
        return null;
      }

      if (!preferDirectMp4OnIos) {
        final dashPlayback = await _tryResolveDash(
          result: result,
          title: (viewData['title'] as String?)?.trim().isNotEmpty == true
              ? viewData['title'] as String
              : result.title,
          cid: cid.toInt(),
        );
        if (dashPlayback != null) {
          // #region debug-point A:dash-selected
          unawaited(_reportResolverDebugEvent(
            hypothesisId: 'A',
            location: 'bilibili_playback_resolver.dart:resolve:dash',
            message: 'Resolved Bilibili DASH playback',
            data: {
              'bvid': result.id,
              'primaryUrl': _debugShortMediaUrl(dashPlayback.primaryUrl),
              'secondaryUrl': dashPlayback.secondaryUrl == null
                  ? null
                  : _debugShortMediaUrl(dashPlayback.secondaryUrl!),
              'displayLabel': dashPlayback.displayLabel,
            },
          ));
          // #endregion
          return dashPlayback;
        }
      }

      final playData = await _fetchPlayUrl(
        bvid: result.id,
        cid: cid.toInt(),
      );

      final durl = (playData['durl'] as List?) ?? const [];
      if (durl.isEmpty) {
        return null;
      }

      final first = durl.first;
      if (first is! Map<String, dynamic>) {
        return null;
      }

      final mediaUrl = first['url'];
      if (mediaUrl is! String || mediaUrl.isEmpty) {
        return null;
      }

      final quality = playData['quality'];
      // #region debug-point A:mp4-selected
      unawaited(_reportResolverDebugEvent(
        hypothesisId: 'A',
        location: 'bilibili_playback_resolver.dart:resolve:mp4',
        message: 'Resolved Bilibili direct MP4 playback',
        data: {
          'bvid': result.id,
          'preferDirectMp4OnIos': preferDirectMp4OnIos,
          'quality': quality,
          'mediaUrl': _debugShortMediaUrl(mediaUrl),
        },
      ));
      // #endregion
      return PlaybackDescriptor(
        kind: PlaybackKind.nativeStream,
        primaryUrl: mediaUrl,
        fallbackUrl: result.playUrl,
        title: (viewData['title'] as String?)?.trim().isNotEmpty == true
            ? viewData['title'] as String
            : result.title,
        displayLabel: _buildMp4DisplayLabel(quality),
        mimeType: 'video/mp4',
        headers: const {
          'User-Agent': _userAgent,
          'Referer': 'https://www.bilibili.com',
          'Origin': 'https://www.bilibili.com',
          'Accept': '*/*',
          'Range': 'bytes=0-',
        },
      );
    } catch (_) {
      return null;
    }
  }

  Future<PlaybackDescriptor?> _tryResolveDash({
    required SearchResult result,
    required String title,
    required int cid,
  }) async {
    try {
      final playData = await _fetchDashPlayUrl(
        bvid: result.id,
        cid: cid,
      );
      final dash = playData['dash'];
      if (dash is! Map<String, dynamic>) {
        return null;
      }

      final videoTracks = (dash['video'] as List?) ?? const [];
      final audioTracks = (dash['audio'] as List?) ?? const [];
      if (videoTracks.isEmpty || audioTracks.isEmpty) {
        return null;
      }

      final bestVideo = _pickBestDashVideo(videoTracks);
      final bestAudio = _pickBestDashAudio(audioTracks);
      if (bestVideo == null || bestAudio == null) {
        return null;
      }

      final videoUrl = bestVideo['baseUrl'] ?? bestVideo['base_url'];
      final audioUrl = bestAudio['baseUrl'] ?? bestAudio['base_url'];
      if (videoUrl is! String ||
          videoUrl.isEmpty ||
          audioUrl is! String ||
          audioUrl.isEmpty) {
        return null;
      }

      // #region debug-point A:dash-track-picked
      unawaited(_reportResolverDebugEvent(
        hypothesisId: 'A',
        location: 'bilibili_playback_resolver.dart:_tryResolveDash',
        message: 'Picked DASH video/audio tracks',
        data: {
          'bvid': result.id,
          'videoId': bestVideo['id'],
          'videoCodec': bestVideo['codecs'],
          'videoBandwidth': bestVideo['bandwidth'],
          'videoUrl': _debugShortMediaUrl(videoUrl),
          'audioId': bestAudio['id'],
          'audioCodec': bestAudio['codecs'],
          'audioBandwidth': bestAudio['bandwidth'],
          'audioUrl': _debugShortMediaUrl(audioUrl),
        },
      ));
      // #endregion

      return PlaybackDescriptor(
        kind: PlaybackKind.nativeStream,
        primaryUrl: videoUrl,
        secondaryUrl: audioUrl,
        fallbackUrl: result.playUrl,
        title: title,
        displayLabel: _buildDashDisplayLabel(bestVideo['id']),
        mimeType: 'video/mp4',
        headers: const {
          'User-Agent': _userAgent,
          'Referer': 'https://www.bilibili.com',
          'Origin': 'https://www.bilibili.com',
          'Accept': '*/*',
          'Range': 'bytes=0-',
        },
      );
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> _fetchView(String bvid) async {
    final uri = Uri.https('api.bilibili.com', '/x/web-interface/view', {
      'bvid': bvid,
    });
    final response = await http.get(uri, headers: _headers);
    return _decodeBilibiliPayload(response.body, response.statusCode);
  }

  Future<Map<String, dynamic>> _fetchPlayUrl({
    required String bvid,
    required int cid,
  }) async {
    final candidates = [
      {
        'bvid': bvid,
        'cid': '$cid',
        'qn': '80',
        'fnval': '1',
        'platform': 'html5',
        'high_quality': '1',
        'try_look': '1',
      },
      {
        'bvid': bvid,
        'cid': '$cid',
        'qn': '64',
        'fnval': '1',
        'platform': 'html5',
        'high_quality': '1',
        'try_look': '1',
      },
      {
        'bvid': bvid,
        'cid': '$cid',
        'qn': '32',
        'fnval': '1',
        'platform': 'html5',
      },
    ];

    Object? lastError;
    for (final params in candidates) {
      try {
        final uri = Uri.https('api.bilibili.com', '/x/player/playurl', params);
        final response = await http.get(uri, headers: _headers);
        return _decodeBilibiliPayload(response.body, response.statusCode);
      } catch (error) {
        lastError = error;
      }
    }
    throw Exception('Bilibili playurl 获取失败: $lastError');
  }

  Future<Map<String, dynamic>> _fetchDashPlayUrl({
    required String bvid,
    required int cid,
  }) async {
    final candidates = [
      {
        'bvid': bvid,
        'cid': '$cid',
        'qn': '112',
        'fnval': '16',
        'fourk': '1',
      },
      {
        'bvid': bvid,
        'cid': '$cid',
        'qn': '80',
        'fnval': '16',
        'fourk': '0',
      },
      {
        'bvid': bvid,
        'cid': '$cid',
        'qn': '64',
        'fnval': '16',
        'fourk': '0',
      },
    ];

    Object? lastError;
    for (final params in candidates) {
      try {
        final uri = Uri.https('api.bilibili.com', '/x/player/playurl', params);
        final response = await http.get(uri, headers: _headers);
        final data = _decodeBilibiliPayload(response.body, response.statusCode);
        final dash = data['dash'];
        if (dash is Map<String, dynamic> &&
            ((dash['video'] as List?)?.isNotEmpty ?? false) &&
            ((dash['audio'] as List?)?.isNotEmpty ?? false)) {
          return data;
        }
      } catch (error) {
        lastError = error;
      }
    }
    throw Exception('Bilibili DASH 获取失败: $lastError');
  }

  Map<String, dynamic> _decodeBilibiliPayload(String body, int statusCode) {
    if (statusCode != 200) {
      throw Exception('Bilibili HTTP 状态异常: $statusCode');
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Bilibili 返回了非预期数据结构');
    }

    final code = decoded['code'];
    if (code != 0) {
      throw Exception(
        'Bilibili API 返回异常: code=$code, message=${decoded['message']}',
      );
    }

    final data = decoded['data'];
    if (data is! Map<String, dynamic>) {
      throw Exception('Bilibili data 字段缺失');
    }
    return data;
  }

  Map<String, String> get _headers => const {
        'User-Agent': _userAgent,
        'Referer': 'https://www.bilibili.com',
        'Origin': 'https://www.bilibili.com',
        'Accept': 'application/json, text/plain, */*',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      };

  Map<String, dynamic>? _pickBestDashVideo(List tracks) {
    final normalized = tracks
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    if (normalized.isEmpty) {
      return null;
    }
    normalized.sort((a, b) {
      final idA = (a['id'] as num?)?.toInt() ?? 0;
      final idB = (b['id'] as num?)?.toInt() ?? 0;
      final bandwidthA = (a['bandwidth'] as num?)?.toInt() ?? 0;
      final bandwidthB = (b['bandwidth'] as num?)?.toInt() ?? 0;
      final widthA = (a['width'] as num?)?.toInt() ?? 0;
      final widthB = (b['width'] as num?)?.toInt() ?? 0;
      final heightA = (a['height'] as num?)?.toInt() ?? 0;
      final heightB = (b['height'] as num?)?.toInt() ?? 0;
      return (idA * 100000000 + bandwidthA + widthA * heightA)
          .compareTo(idB * 100000000 + bandwidthB + widthB * heightB);
    });
    return normalized.last;
  }

  Map<String, dynamic>? _pickBestDashAudio(List tracks) {
    final normalized = tracks
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    if (normalized.isEmpty) {
      return null;
    }
    normalized.sort((a, b) {
      final bandwidthA = (a['bandwidth'] as num?)?.toInt() ?? 0;
      final bandwidthB = (b['bandwidth'] as num?)?.toInt() ?? 0;
      final idA = (a['id'] as num?)?.toInt() ?? 0;
      final idB = (b['id'] as num?)?.toInt() ?? 0;
      return (bandwidthA * 1000 + idA).compareTo(bandwidthB * 1000 + idB);
    });
    return normalized.last;
  }

  String _buildMp4DisplayLabel(Object? quality) {
    switch (quality) {
      case 80:
        return 'Bilibili 直解析 1080P';
      case 64:
        return 'Bilibili 直解析 720P';
      case 32:
        return 'Bilibili 直解析 480P';
      case 16:
        return 'Bilibili 直解析 360P';
      default:
        return 'Bilibili 直解析';
    }
  }

  String _buildDashDisplayLabel(Object? quality) {
    switch (quality) {
      case 120:
        return 'Bilibili DASH 4K';
      case 116:
        return 'Bilibili DASH 1080P60';
      case 112:
        return 'Bilibili DASH 1080P+';
      case 80:
        return 'Bilibili DASH 1080P';
      case 64:
        return 'Bilibili DASH 720P';
      case 32:
        return 'Bilibili DASH 480P';
      default:
        return 'Bilibili DASH';
    }
  }
}
