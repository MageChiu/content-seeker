import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../../models/search_result.dart';
import 'local_source_debug.dart';

class BilibiliSearchEngine {
  static const String _source = 'bilibili';
  static const int _maxAttempts = 3;
  static const Duration _requestTimeout = Duration(seconds: 12);
  static const Duration _anonymousCookieTtl = Duration(hours: 6);
  static const Duration _wbiKeyTtl = Duration(minutes: 30);
  static const String _webHost = 'www.bilibili.com';
  static const String _apiHost = 'api.bilibili.com';
  static const String _userAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/123.0.0.0 Safari/537.36';

  static final LocalSourceRateLimitState _rateLimitState =
      LocalSourceRateLimitState();
  static final Map<String, String> _anonymousCookies = <String, String>{};

  static DateTime? _anonymousCookiesFetchedAt;
  static String _cachedMixinKey = '';
  static DateTime? _cachedMixinKeyFetchedAt;

  final Map<String, String> credentials;

  const BilibiliSearchEngine({
    this.credentials = const <String, String>{},
  });

  Future<List<SearchResult>> searchVideos(
    String query, {
    int page = 1,
    int limit = 20,
  }) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      return const <SearchResult>[];
    }
    if (_rateLimitState.isCoolingDown) {
      reportLocalSourceDebug(
        source: _source,
        location: 'bilibili_search_engine.dart:searchVideos',
        msg: 'skip search during cooldown',
        data: <String, dynamic>{
          'query': normalizedQuery,
          'remainingMs': _rateLimitState.remainingCooldown.inMilliseconds,
        },
      );
      return const <SearchResult>[];
    }

    Object? lastError;
    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        final results = await _searchOnce(
          normalizedQuery,
          page: page,
          limit: limit,
          attempt: attempt,
        );
        _rateLimitState.onSuccess();
        reportLocalSourceDebug(
          source: _source,
          location: 'bilibili_search_engine.dart:searchVideos',
          msg: 'search succeeded',
          data: <String, dynamic>{
            'query': normalizedQuery,
            'attempt': attempt,
            'resultCount': results.length,
          },
        );
        return results;
      } catch (error) {
        lastError = error;
        reportLocalSourceDebug(
          source: _source,
          location: 'bilibili_search_engine.dart:searchVideos',
          msg: 'search request failed',
          data: <String, dynamic>{
            'query': normalizedQuery,
            'attempt': attempt,
            'error': error.toString(),
          },
        );

        if (_isCooldownWorthyError(error)) {
          final retryAfterSeconds =
              error is _BilibiliSearchException ? error.retryAfterSeconds : null;
          final cooldown = _rateLimitState.activateCooldown(
            retryAfterSeconds: retryAfterSeconds,
          );
          reportLocalSourceDebug(
            source: _source,
            location: 'bilibili_search_engine.dart:searchVideos',
            msg: 'risk control cooldown activated',
            data: <String, dynamic>{
              'query': normalizedQuery,
              'attempt': attempt,
              'cooldownMs': cooldown.inMilliseconds,
              'error': error.toString(),
            },
          );
        }

        if (attempt >= _maxAttempts ||
            !_isRetryableError(error) ||
            _rateLimitState.isCoolingDown) {
          break;
        }

        final delay = retryDelayForAttempt(
          attempt,
          rateLimited: _isCooldownWorthyError(error),
        );
        reportLocalSourceDebug(
          source: _source,
          location: 'bilibili_search_engine.dart:searchVideos',
          msg: 'retry scheduled',
          data: <String, dynamic>{
            'query': normalizedQuery,
            'attempt': attempt,
            'nextAttempt': attempt + 1,
            'delayMs': delay.inMilliseconds,
          },
        );
        await Future<void>.delayed(delay);
      }
    }

    reportLocalSourceDebug(
      source: _source,
      location: 'bilibili_search_engine.dart:searchVideos',
      msg: 'search degraded to empty result',
      data: <String, dynamic>{
        'query': normalizedQuery,
        'error': lastError?.toString(),
      },
    );
    return const <SearchResult>[];
  }

  Future<List<SearchResult>> _searchOnce(
    String query, {
    required int page,
    required int limit,
    required int attempt,
  }) async {
    await _ensureAnonymousCookies();
    final mixinKey = await _ensureMixinKey();
    final effectiveCookies = _buildEffectiveCookies();

    final uri = _buildSignedUri(
      host: _apiHost,
      path: '/x/web-interface/wbi/search/type',
      params: <String, String>{
        'search_type': 'video',
        'keyword': query,
        'page': '$page',
        'page_size': '${limit.clamp(1, 50)}',
      },
      mixinKey: mixinKey,
    );

    reportLocalSourceDebug(
      source: _source,
      location: 'bilibili_search_engine.dart:_searchOnce',
      msg: 'request start',
      data: <String, dynamic>{
        'query': query,
        'page': page,
        'limit': limit,
        'attempt': attempt,
        'uri': uri.toString(),
        'cookieKeys': effectiveCookies.keys.toList(growable: false),
      },
    );

    final response = await _sendGet(
      uri,
      cookies: effectiveCookies,
      persistAnonymousCookies: credentials.isEmpty,
    );

    reportLocalSourceDebug(
      source: _source,
      location: 'bilibili_search_engine.dart:_searchOnce',
      msg: 'response received',
      data: <String, dynamic>{
        'query': query,
        'attempt': attempt,
        'statusCode': response.statusCode,
        'bodyPreview': bodyPreview(response.body),
      },
    );

    if (response.statusCode != 200) {
      throw _BilibiliSearchException(
        message: 'Bilibili 搜索 HTTP 状态异常',
        uri: uri,
        statusCode: response.statusCode,
        bodyPreview: bodyPreview(response.body),
        retryAfterSeconds: response.retryAfterSeconds,
      );
    }

    final body = response.body.trimLeft();
    if (body.startsWith('<!DOCTYPE html') || body.startsWith('<html')) {
      throw _BilibiliSearchException(
        message: 'Bilibili 返回了 HTML 页面，可能触发了风控',
        uri: uri,
        bodyPreview: bodyPreview(response.body),
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw _BilibiliSearchException(
        message: 'Bilibili 返回了非预期响应结构',
        uri: uri,
        bodyPreview: bodyPreview(response.body),
      );
    }

    final apiCode = _readInt(decoded['code']);
    if (apiCode != 0) {
      throw _BilibiliSearchException(
        message:
            'Bilibili 搜索业务错误: code=$apiCode, message=${decoded['message']}',
        uri: uri,
        statusCode: response.statusCode,
        apiCode: apiCode,
        bodyPreview: bodyPreview(response.body),
      );
    }

    final items = decoded['data']?['result'] as List? ?? const <dynamic>[];
    final results = items
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .map(_mapItemToSearchResult)
        .whereType<SearchResult>()
        .toList(growable: false);

    reportLocalSourceDebug(
      source: _source,
      location: 'bilibili_search_engine.dart:_searchOnce',
      msg: 'response parsed',
      data: <String, dynamic>{
        'query': query,
        'attempt': attempt,
        'rawItemCount': items.length,
        'resultCount': results.length,
      },
    );
    return results;
  }

  Future<void> _ensureAnonymousCookies() async {
    final now = DateTime.now();
    final hasBuvid3 = _anonymousCookies['buvid3']?.trim().isNotEmpty == true;
    if (hasBuvid3 &&
        _anonymousCookiesFetchedAt != null &&
        now.difference(_anonymousCookiesFetchedAt!) < _anonymousCookieTtl) {
      return;
    }

    final homeUri = Uri.https(_webHost, '/');
    final homeResponse = await _sendGet(
      homeUri,
      cookies: const <String, String>{},
      persistAnonymousCookies: true,
    );
    if (homeResponse.statusCode != 200) {
      throw _BilibiliSearchException(
        message: 'Bilibili 首页 bootstrap 失败',
        uri: homeUri,
        statusCode: homeResponse.statusCode,
        bodyPreview: bodyPreview(homeResponse.body),
        retryAfterSeconds: homeResponse.retryAfterSeconds,
      );
    }
    _anonymousCookiesFetchedAt = DateTime.now();

    reportLocalSourceDebug(
      source: _source,
      location: 'bilibili_search_engine.dart:_ensureAnonymousCookies',
      msg: 'anonymous cookies refreshed',
      data: <String, dynamic>{
        'cookieKeys': _anonymousCookies.keys.toList(growable: false),
      },
    );
  }

  Future<String> _ensureMixinKey() async {
    final now = DateTime.now();
    if (_cachedMixinKey.isNotEmpty &&
        _cachedMixinKeyFetchedAt != null &&
        now.difference(_cachedMixinKeyFetchedAt!) < _wbiKeyTtl) {
      return _cachedMixinKey;
    }

    final navUri = Uri.https(_apiHost, '/x/web-interface/nav');
    final navResponse = await _sendGet(
      navUri,
      cookies: _anonymousCookies,
      persistAnonymousCookies: true,
    );
    if (navResponse.statusCode != 200) {
      throw _BilibiliSearchException(
        message: 'Bilibili nav 请求失败',
        uri: navUri,
        statusCode: navResponse.statusCode,
        bodyPreview: bodyPreview(navResponse.body),
        retryAfterSeconds: navResponse.retryAfterSeconds,
      );
    }

    final decoded = jsonDecode(navResponse.body);
    if (decoded is! Map<String, dynamic>) {
      throw _BilibiliSearchException(
        message: 'Bilibili nav 响应结构异常',
        uri: navUri,
        bodyPreview: bodyPreview(navResponse.body),
      );
    }

    final data = decoded['data'];
    final imgUrl = '${data?['wbi_img']?['img_url'] ?? ''}'.trim();
    final subUrl = '${data?['wbi_img']?['sub_url'] ?? ''}'.trim();
    final mixinKey = _extractMixinKey(imgUrl, subUrl);
    if (mixinKey.isEmpty) {
      throw _BilibiliSearchException(
        message: 'Bilibili WBI key 解析失败',
        uri: navUri,
        bodyPreview: bodyPreview(navResponse.body),
      );
    }

    _cachedMixinKey = mixinKey;
    _cachedMixinKeyFetchedAt = DateTime.now();
    return mixinKey;
  }

  Map<String, String> _buildEffectiveCookies() {
    final cookies = <String, String>{..._anonymousCookies};
    cookies.addAll(_buildCredentialCookies());
    return cookies;
  }

  Map<String, String> _buildCredentialCookies() {
    final cookies = <String, String>{};
    _mergeCookieHeader(cookies, credentials['cookie'] ?? '');

    final mapping = <String, String>{
      'sessdata': 'SESSDATA',
      'SESSDATA': 'SESSDATA',
      'buvid3': 'buvid3',
      'buvid4': 'buvid4',
      'bili_jct': 'bili_jct',
      'DedeUserID': 'DedeUserID',
      'dedeuserid': 'DedeUserID',
    };
    for (final entry in mapping.entries) {
      final value = (credentials[entry.key] ?? '').trim();
      if (value.isNotEmpty) {
        cookies[entry.value] = value;
      }
    }
    return cookies;
  }

  void _mergeCookieHeader(Map<String, String> target, String rawCookie) {
    final normalized = rawCookie.trim();
    if (normalized.isEmpty) {
      return;
    }
    final ignoredKeys = <String>{
      'path',
      'domain',
      'max-age',
      'expires',
      'samesite',
      'secure',
      'httponly',
    };
    for (final segment in normalized.split(';')) {
      final item = segment.trim();
      if (item.isEmpty || !item.contains('=')) {
        continue;
      }
      final index = item.indexOf('=');
      final key = item.substring(0, index).trim();
      if (key.isEmpty || ignoredKeys.contains(key.toLowerCase())) {
        continue;
      }
      final value = item.substring(index + 1).trim();
      if (value.isNotEmpty) {
        target[key] = value;
      }
    }
  }

  Uri _buildSignedUri({
    required String host,
    required String path,
    required Map<String, String> params,
    required String mixinKey,
  }) {
    final signedParams = <String, String>{...params};
    signedParams['wts'] =
        (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();

    final sortedKeys = signedParams.keys.toList(growable: false)..sort();
    final query = sortedKeys
        .map(
          (key) =>
              '${Uri.encodeQueryComponent(key)}='
              '${Uri.encodeQueryComponent(_filterWbiValue(signedParams[key] ?? ''))}',
        )
        .join('&');
    final wRid = md5.convert(utf8.encode('$query$mixinKey')).toString();
    return Uri.parse('https://$host$path?$query&w_rid=$wRid');
  }

  String _filterWbiValue(String value) {
    return value.replaceAll(RegExp(r"[!'()*]"), '');
  }

  String _extractMixinKey(String imgUrl, String subUrl) {
    final imgKey = _extractKeyFromUrl(imgUrl);
    final subKey = _extractKeyFromUrl(subUrl);
    final raw = '$imgKey$subKey';
    if (raw.isEmpty) {
      return '';
    }

    const mixinKeyEncTab = <int>[
      46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35,
      27, 43, 5, 49, 33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13,
      37, 48, 7, 16, 24, 55, 40, 61, 26, 17, 0, 1, 60, 51, 30, 4,
      22, 25, 54, 21, 56, 59, 6, 63, 57, 62, 11, 36, 20, 34, 44, 52,
    ];

    final buffer = StringBuffer();
    for (final index in mixinKeyEncTab.take(32)) {
      if (index >= 0 && index < raw.length) {
        buffer.write(raw[index]);
      }
    }
    return buffer.toString();
  }

  String _extractKeyFromUrl(String url) {
    final normalized = url.trim();
    if (normalized.isEmpty) {
      return '';
    }
    final segments = Uri.tryParse(normalized)?.pathSegments;
    if (segments == null || segments.isEmpty) {
      return '';
    }
    final fileName = segments.last;
    final dotIndex = fileName.lastIndexOf('.');
    return dotIndex >= 0 ? fileName.substring(0, dotIndex) : fileName;
  }

  Future<_BilibiliHttpResponse> _sendGet(
    Uri uri, {
    required Map<String, String> cookies,
    required bool persistAnonymousCookies,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri).timeout(_requestTimeout);
      request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
      request.headers.set(HttpHeaders.refererHeader, 'https://www.bilibili.com/');
      request.headers.set('Origin', 'https://www.bilibili.com');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json, text/plain, */*');
      request.headers.set(HttpHeaders.acceptLanguageHeader, 'zh-CN,zh;q=0.9');
      if (cookies.isNotEmpty) {
        request.headers.set(HttpHeaders.cookieHeader, _formatCookieHeader(cookies));
      }

      final response = await request.close().timeout(_requestTimeout);
      final body = await utf8.decodeStream(response);
      if (persistAnonymousCookies && response.cookies.isNotEmpty) {
        for (final cookie in response.cookies) {
          if (cookie.name.trim().isNotEmpty && cookie.value.trim().isNotEmpty) {
            _anonymousCookies[cookie.name] = cookie.value;
          }
        }
      }
      return _BilibiliHttpResponse(
        statusCode: response.statusCode,
        body: body,
        retryAfterSeconds: _parseRetryAfterSeconds(response.headers),
      );
    } finally {
      client.close(force: true);
    }
  }

  String _formatCookieHeader(Map<String, String> cookies) {
    return cookies.entries
        .where((entry) => entry.key.trim().isNotEmpty && entry.value.trim().isNotEmpty)
        .map((entry) => '${entry.key}=${entry.value}')
        .join('; ');
  }

  int? _parseRetryAfterSeconds(HttpHeaders headers) {
    final header = headers.value(HttpHeaders.retryAfterHeader);
    if (header == null || header.trim().isEmpty) {
      return null;
    }
    final direct = int.tryParse(header.trim());
    if (direct != null && direct > 0) {
      return direct;
    }
    try {
      final retryAt = HttpDate.parse(header.trim());
      final seconds = retryAt.difference(DateTime.now().toUtc()).inSeconds;
      return seconds > 0 ? seconds : null;
    } catch (_) {
      return null;
    }
  }

  SearchResult? _mapItemToSearchResult(Map<String, dynamic> item) {
    final bvid = '${item['bvid'] ?? ''}'.trim();
    if (bvid.isEmpty) {
      return null;
    }

    var title = '${item['title'] ?? ''}'.trim();
    title = title.replaceAll(RegExp(r'<[^>]*>'), '');

    var description = '${item['description'] ?? ''}'.trim();
    description = description.replaceAll(RegExp(r'<[^>]*>'), '');

    var pic = '${item['pic'] ?? ''}'.trim();
    if (pic.startsWith('//')) {
      pic = 'https:$pic';
    }

    final playUrl = 'https://www.bilibili.com/video/$bvid';
    return SearchResult(
      id: bvid,
      title: title,
      source: 'bilibili',
      mediaType: MediaType.video,
      mediaSubtype: MediaSubtype.video,
      thumbnailUrl: pic,
      durationSeconds: _parseDuration('${item['duration'] ?? ''}'),
      playUrl: playUrl,
      playbackKind: SearchPlaybackKind.externalOpen,
      isPlayable: true,
      availability: ResultAvailability.available,
      sourceTier: SourceTier.publicApi,
      canonicalUrl: playUrl,
      artistOrAuthor: '${item['author'] ?? ''}'.trim(),
      albumOrSeries: '',
      description: description,
    );
  }

  int _parseDuration(String raw) {
    final parts = raw
        .trim()
        .split(':')
        .where((part) => part.trim().isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) {
      return 0;
    }
    try {
      if (parts.length == 2) {
        return int.parse(parts[0]) * 60 + int.parse(parts[1]);
      }
      if (parts.length == 3) {
        return int.parse(parts[0]) * 3600 +
            int.parse(parts[1]) * 60 +
            int.parse(parts[2]);
      }
    } catch (_) {
      return 0;
    }
    return 0;
  }

  int _readInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.round();
    }
    return int.tryParse('$value') ?? 0;
  }

  bool _isRetryableError(Object error) {
    if (error is TimeoutException ||
        error is SocketException ||
        error is HttpException) {
      return true;
    }
    if (error is! _BilibiliSearchException) {
      return false;
    }

    final statusCode = error.statusCode;
    if (statusCode != null &&
        (statusCode == 408 ||
            statusCode == 409 ||
            statusCode == 425 ||
            statusCode == 429 ||
            statusCode >= 500)) {
      return true;
    }

    final apiCode = error.apiCode;
    return apiCode == -352 || apiCode == -799;
  }

  bool _isCooldownWorthyError(Object error) {
    if (error is! _BilibiliSearchException) {
      return false;
    }
    final statusCode = error.statusCode;
    if (statusCode == 412 || statusCode == 429) {
      return true;
    }
    final apiCode = error.apiCode;
    return apiCode == -352 || apiCode == -412 || apiCode == -799;
  }
}

class _BilibiliHttpResponse {
  final int statusCode;
  final String body;
  final int? retryAfterSeconds;

  const _BilibiliHttpResponse({
    required this.statusCode,
    required this.body,
    this.retryAfterSeconds,
  });
}

class _BilibiliSearchException implements Exception {
  final String message;
  final Uri uri;
  final int? statusCode;
  final int? apiCode;
  final String bodyPreview;
  final int? retryAfterSeconds;

  const _BilibiliSearchException({
    required this.message,
    required this.uri,
    this.statusCode,
    this.apiCode,
    this.bodyPreview = '',
    this.retryAfterSeconds,
  });

  @override
  String toString() {
    final parts = <String>[
      message,
      'uri=$uri',
      if (statusCode != null) 'status=$statusCode',
      if (apiCode != null) 'code=$apiCode',
      if (retryAfterSeconds != null) 'retry_after=$retryAfterSeconds',
      if (bodyPreview.isNotEmpty) 'body=$bodyPreview',
    ];
    return parts.join(', ');
  }
}
