import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class DirectoryAccessResult {
  final String path;
  final String bookmark;
  final bool hasAccess;
  final bool writable;
  final String error;

  const DirectoryAccessResult({
    required this.path,
    this.bookmark = '',
    this.hasAccess = false,
    this.writable = false,
    this.error = '',
  });
}

class DirectoryAccess {
  static const MethodChannel _channel =
      MethodChannel('content_seeker/directory_access');

  static bool get _isMacOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  static Future<DirectoryAccessResult?> pickDirectory() async {
    if (!_isMacOS) return null;
    final result =
        await _channel.invokeMapMethod<String, dynamic>('pickDirectory');
    if (result == null) return null;
    final path = (result['path'] as String? ?? '').trim();
    if (path.isEmpty) return null;
    return DirectoryAccessResult(
      path: path,
      bookmark: (result['bookmark'] as String? ?? '').trim(),
      hasAccess: result['hasAccess'] as bool? ?? true,
      writable: result['writable'] as bool? ?? false,
      error: (result['error'] as String? ?? '').trim(),
    );
  }

  static Future<DirectoryAccessResult?> resolveBookmark(String bookmark) async {
    final trimmed = bookmark.trim();
    if (!_isMacOS || trimmed.isEmpty) return null;
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'resolveBookmark',
      {'bookmark': trimmed},
    );
    if (result == null) return null;
    final path = (result['path'] as String? ?? '').trim();
    if (path.isEmpty) return null;
    return DirectoryAccessResult(
      path: path,
      bookmark: (result['bookmark'] as String? ?? '').trim(),
      hasAccess: result['hasAccess'] as bool? ?? true,
      writable: result['writable'] as bool? ?? false,
      error: (result['error'] as String? ?? '').trim(),
    );
  }
}
