// 通道 1: Bilibili 客户端直调（公开搜索，无需 Key）
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../../../core/search_source.dart';
import '../../../models/search_result.dart';

// #region debug-point C:bilibili-request
void _debugReportBilibili(String msg, Map<String, dynamic> data) {
  final client = HttpClient();
  unawaited(() async {
    try {
      final request = await client.postUrl(Uri.parse('http://127.0.0.1:7777/event'));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'sessionId': 'local-bilibili-search',
        'runId': 'pre-fix',
        'hypothesisId': 'C',
        'location': 'bilibili_local_source.dart:search',
        'msg': '[DEBUG] $msg',
        'data': data,
        'ts': DateTime.now().millisecondsSinceEpoch,
      }));
      final response = await request.close();
      await response.drain<void>();
      client.close();
    } catch (_) {
      client.close(force: true);
    }
  }());
}
// #endregion

class BilibiliLocalSource implements SearchSource {
  static const int _maxAttempts = 3;

  @override
  String get name => 'bilibili_local';

  @override
  bool get isConfigured => true; // Bilibili 公开 API 无需配置

  @override
  Future<List<SearchResult>> search(String query,
      {int page = 1, int limit = 20}) async {
    Object? lastError;

    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        final uri =
            Uri.https('api.bilibili.com', '/x/web-interface/search/type', {
          'search_type': 'video',
          'keyword': query,
          'page': '$page',
          'page_size': '$limit',
        });
        // #region debug-point C:request-start
        _debugReportBilibili('bilibili request start', {
          'query': query,
          'page': page,
          'limit': limit,
          'attempt': attempt,
          'uri': uri.toString(),
        });
        // #endregion

        final response = await http.get(uri, headers: {
          'User-Agent':
              'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36',
          'Referer': 'https://www.bilibili.com',
          'Origin': 'https://www.bilibili.com',
          'Accept': 'application/json, text/plain, */*',
          'Accept-Language': 'zh-CN,zh;q=0.9',
        });
        // #region debug-point C:request-response
        _debugReportBilibili('bilibili response received', {
          'attempt': attempt,
          'statusCode': response.statusCode,
          'bodyPreview': response.body.substring(
            0,
            response.body.length > 300 ? 300 : response.body.length,
          ),
        });
        // #endregion

        if (response.statusCode != 200) {
          throw Exception('Bilibili 搜索 HTTP 状态异常: ${response.statusCode}');
        }
        final body = response.body;
        if (body.trimLeft().startsWith('<!DOCTYPE html') ||
            body.trimLeft().startsWith('<html')) {
          throw Exception('Bilibili 返回了 HTML 错误页，可能触发了风控或临时错误');
        }

        final data = jsonDecode(body);
        if (data is! Map<String, dynamic>) {
          throw Exception('Bilibili 返回了非预期响应结构');
        }
        if (data['code'] != 0) {
          throw Exception(
            'Bilibili 搜索失败: code=${data['code']}, message=${data['message']}',
          );
        }
        final items = data['data']?['result'] as List? ?? [];
        // #region debug-point C:response-parsed
        _debugReportBilibili('bilibili response parsed', {
          'attempt': attempt,
          'itemCount': items.length,
          'code': data['code'],
          'message': data['message'],
        });
        // #endregion

        return items.map((item) {
          final bvid = item['bvid'] ?? '';
          String title = (item['title'] ?? '')
              .replaceAll(RegExp(r'<em class="keyword">'), '')
              .replaceAll('</em>', '');
          String pic = item['pic'] ?? '';
          if (pic.startsWith('//')) pic = 'https:$pic';

          return SearchResult(
            id: bvid,
            title: title,
            source: 'bilibili',
            mediaType: MediaType.video,
            mediaSubtype: MediaSubtype.video,
            thumbnailUrl: pic,
            durationSeconds: _parseDuration(item['duration'] ?? '0:0'),
            playUrl: 'https://www.bilibili.com/video/$bvid',
            playbackKind: SearchPlaybackKind.externalOpen,
            isPlayable: true,
            availability: ResultAvailability.available,
            sourceTier: SourceTier.publicApi,
            canonicalUrl: 'https://www.bilibili.com/video/$bvid',
            artistOrAuthor: item['author'] ?? '',
            albumOrSeries: '',
            description: item['description'] ?? '',
          );
        }).toList();
      } catch (e) {
        lastError = e;
        // #region debug-point C:request-error
        _debugReportBilibili('bilibili request exception', {
          'query': query,
          'attempt': attempt,
          'error': e.toString(),
        });
        // #endregion
        if (attempt >= _maxAttempts || !_isRetryableError(e)) {
          rethrow;
        }
        final delay = Duration(milliseconds: 300 * attempt);
        // #region debug-point C:retry
        _debugReportBilibili('bilibili retry scheduled', {
          'query': query,
          'attempt': attempt,
          'nextAttempt': attempt + 1,
          'delayMs': delay.inMilliseconds,
          'error': e.toString(),
        });
        // #endregion
        await Future<void>.delayed(delay);
      }
    }

    throw Exception('Bilibili 搜索失败: $lastError');
  }

  static int _parseDuration(String d) {
    try {
      final parts = d.split(':');
      if (parts.length == 2) {
        return int.parse(parts[0]) * 60 + int.parse(parts[1]);
      } else if (parts.length == 3) {
        return int.parse(parts[0]) * 3600 +
            int.parse(parts[1]) * 60 +
            int.parse(parts[2]);
      }
    } catch (_) {}
    return 0;
  }

  static bool _isRetryableError(Object error) {
    final message = error.toString();
    return message.contains('412') ||
        message.contains('429') ||
        message.contains('HTML 错误页') ||
        message.contains('Connection failed') ||
        message.contains('SocketException') ||
        message.contains('timed out');
  }
}
