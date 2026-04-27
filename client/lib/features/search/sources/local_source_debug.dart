import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

void reportLocalSourceDebug({
  required String source,
  required String location,
  required String msg,
  Map<String, dynamic> data = const {},
}) {
  final payload = <String, dynamic>{
    'source': source,
    ...data,
  };
  debugPrint('[local-source][$source] $msg ${jsonEncode(payload)}');

  final client = HttpClient();
  unawaited(() async {
    try {
      final request = await client.postUrl(Uri.parse('http://127.0.0.1:7777/event'));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'sessionId': 'local-media-sources',
        'runId': 'rate-limit-hardening',
        'hypothesisId': source,
        'location': location,
        'msg': '[DEBUG] $msg',
        'data': payload,
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

class LocalSourceHttpException implements Exception {
  final String message;
  final Uri uri;
  final int statusCode;
  final String bodyPreview;
  final int? retryAfterSeconds;

  const LocalSourceHttpException({
    required this.message,
    required this.uri,
    required this.statusCode,
    required this.bodyPreview,
    this.retryAfterSeconds,
  });

  @override
  String toString() {
    final retryAfterSuffix = retryAfterSeconds == null
        ? ''
        : ', retry_after=$retryAfterSeconds';
    return '$message (status=$statusCode, uri=$uri$retryAfterSuffix)';
  }
}

class LocalSourceRateLimitState {
  DateTime? _cooldownUntil;
  int _rateLimitCount = 0;

  bool get isCoolingDown =>
      _cooldownUntil != null && DateTime.now().isBefore(_cooldownUntil!);

  Duration get remainingCooldown {
    final until = _cooldownUntil;
    if (until == null) {
      return Duration.zero;
    }
    final remaining = until.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  Duration activateCooldown({int? retryAfterSeconds}) {
    _rateLimitCount += 1;
    final seconds = retryAfterSeconds != null && retryAfterSeconds > 0
        ? retryAfterSeconds
        : _fallbackCooldownSeconds();
    final duration = Duration(seconds: seconds);
    _cooldownUntil = DateTime.now().add(duration);
    return duration;
  }

  void onSuccess() {
    _rateLimitCount = 0;
    _cooldownUntil = null;
  }

  int _fallbackCooldownSeconds() {
    if (_rateLimitCount <= 1) return 5;
    if (_rateLimitCount == 2) return 10;
    if (_rateLimitCount == 3) return 20;
    return 40;
  }
}

bool isRateLimitedStatus(int statusCode) {
  return statusCode == 412 || statusCode == 429;
}

bool isRetryableStatus(int statusCode) {
  return statusCode == 408 ||
      statusCode == 409 ||
      statusCode == 412 ||
      statusCode == 425 ||
      statusCode == 429 ||
      statusCode >= 500;
}

bool isRetryableLocalSourceError(Object error) {
  if (error is TimeoutException || error is SocketException || error is HttpException) {
    return true;
  }
  if (error is LocalSourceHttpException) {
    return isRetryableStatus(error.statusCode);
  }
  final message = error.toString();
  return message.contains('Connection failed') ||
      message.contains('SocketException') ||
      message.contains('timed out');
}

bool isRateLimitedLocalSourceError(Object error) {
  return error is LocalSourceHttpException && isRateLimitedStatus(error.statusCode);
}

Duration retryDelayForAttempt(
  int attempt, {
  bool rateLimited = false,
}) {
  final boundedAttempt = attempt <= 1 ? 1 : attempt;
  final millis = rateLimited ? 800 * boundedAttempt : 300 * boundedAttempt;
  return Duration(milliseconds: millis);
}

String bodyPreview(String body, {int maxLength = 300}) {
  final normalized = body.replaceAll('\n', ' ').trim();
  if (normalized.length <= maxLength) {
    return normalized;
  }
  return normalized.substring(0, maxLength);
}

int? parseRetryAfterSeconds(http.Response response) {
  final header = response.headers['retry-after'];
  if (header == null || header.trim().isEmpty) {
    return null;
  }

  final direct = int.tryParse(header.trim());
  if (direct != null && direct > 0) {
    return direct;
  }

  final retryAt = HttpDate.parse(header.trim());
  final seconds = retryAt.difference(DateTime.now().toUtc()).inSeconds;
  return seconds > 0 ? seconds : null;
}
