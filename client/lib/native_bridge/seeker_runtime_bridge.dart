import 'dart:async';
import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'native_library_loader.dart';
import 'seeker_bindings.dart';

class RuntimeEvent {
  final int runtimeId;
  final int sessionId;
  final String type;
  final Map<String, dynamic> payload;

  const RuntimeEvent({
    required this.runtimeId,
    required this.sessionId,
    required this.type,
    required this.payload,
  });

  factory RuntimeEvent.fromJson({
    required int runtimeId,
    required int sessionId,
    required String jsonText,
  }) {
    final decoded = jsonDecode(jsonText) as Map<String, dynamic>;
    return RuntimeEvent(
      runtimeId: runtimeId,
      sessionId: sessionId,
      type: '${decoded['type'] ?? 'unknown'}',
      payload: decoded,
    );
  }
}

class SeekerRuntimeBridge {
  final SeekerBindings _bindings = SeekerBindings(loadSeekerLibrary());
  final _eventController = StreamController<RuntimeEvent>.broadcast();

  static SeekerRuntimeBridge? _instance;
  static SeekerRuntimeBridge get instance {
    _instance ??= SeekerRuntimeBridge._();
    return _instance!;
  }

  SeekerRuntimeBridge._();

  Stream<RuntimeEvent> get events => _eventController.stream;

  static final Pointer<NativeFunction<SeekerRuntimeEventCallbackNative>>
      _nativeEventCallback =
      Pointer.fromFunction<SeekerRuntimeEventCallbackNative>(_onRuntimeEvent);

  static void _onRuntimeEvent(
    int runtimeId,
    int sessionId,
    Pointer<Utf8> eventJson,
  ) {
    final instance = _instance;
    if (instance == null || eventJson == nullptr) return;
    final jsonText = eventJson.toDartString();
    instance._eventController.add(
      RuntimeEvent.fromJson(
        runtimeId: runtimeId,
        sessionId: sessionId,
        jsonText: jsonText,
      ),
    );
  }

  int createRuntime({Map<String, dynamic> config = const {}}) {
    final configPtr = jsonEncode(config).toNativeUtf8();
    try {
      return _bindings.runtimeCreate(configPtr);
    } finally {
      calloc.free(configPtr);
    }
  }

  void destroyRuntime(int runtimeId) {
    _bindings.runtimeDestroy(runtimeId);
  }

  int createSession(int runtimeId) {
    return _bindings.sessionCreate(runtimeId, _nativeEventCallback);
  }

  int disposeSession(int runtimeId, int sessionId) {
    return _bindings.sessionDispose(runtimeId, sessionId);
  }

  Map<String, dynamic> resolveMedia(int runtimeId, Map<String, dynamic> request) {
    final requestPtr = jsonEncode(request).toNativeUtf8();
    try {
      final resultPtr = _bindings.resolveMedia(runtimeId, requestPtr);
      final result = resultPtr.toDartString();
      _bindings.freeString(resultPtr);
      return jsonDecode(result) as Map<String, dynamic>;
    } finally {
      calloc.free(requestPtr);
    }
  }

  int sessionOpen(int runtimeId, int sessionId, Map<String, dynamic> resolvedMedia) {
    final resolvedPtr = jsonEncode(resolvedMedia).toNativeUtf8();
    try {
      return _bindings.sessionOpen(runtimeId, sessionId, resolvedPtr);
    } finally {
      calloc.free(resolvedPtr);
    }
  }

  int play(int runtimeId, int sessionId) {
    return _bindings.sessionPlay(runtimeId, sessionId);
  }

  int pause(int runtimeId, int sessionId) {
    return _bindings.sessionPause(runtimeId, sessionId);
  }

  int seek(int runtimeId, int sessionId, int positionMs) {
    return _bindings.sessionSeek(runtimeId, sessionId, positionMs);
  }

  int setRate(int runtimeId, int sessionId, double rate) {
    return _bindings.sessionSetRate(runtimeId, sessionId, rate);
  }

  int setVolume(int runtimeId, int sessionId, double volume) {
    return _bindings.sessionSetVolume(runtimeId, sessionId, volume);
  }

  int selectTrack(int runtimeId, int sessionId, String trackId) {
    final trackPtr = trackId.toNativeUtf8();
    try {
      return _bindings.sessionSelectTrack(runtimeId, sessionId, trackPtr);
    } finally {
      calloc.free(trackPtr);
    }
  }

  int selectVariant(int runtimeId, int sessionId, String variantId) {
    final variantPtr = variantId.toNativeUtf8();
    try {
      return _bindings.sessionSelectVariant(runtimeId, sessionId, variantPtr);
    } finally {
      calloc.free(variantPtr);
    }
  }

  Map<String, dynamic> buildDownloadPlan(
    int runtimeId,
    Map<String, dynamic> resolvedMedia, {
    Map<String, dynamic> options = const {},
  }) {
    final resolvedPtr = jsonEncode(resolvedMedia).toNativeUtf8();
    final optionsPtr = jsonEncode(options).toNativeUtf8();
    try {
      final resultPtr =
          _bindings.buildDownloadPlan(runtimeId, resolvedPtr, optionsPtr);
      final result = resultPtr.toDartString();
      _bindings.freeString(resultPtr);
      return jsonDecode(result) as Map<String, dynamic>;
    } finally {
      calloc.free(resolvedPtr);
      calloc.free(optionsPtr);
    }
  }

  int startDownload(int runtimeId, Map<String, dynamic> downloadPlan) {
    final planPtr = jsonEncode(downloadPlan).toNativeUtf8();
    try {
      return _bindings.downloadStart(runtimeId, planPtr);
    } finally {
      calloc.free(planPtr);
    }
  }

  int pauseDownload(int runtimeId, int downloadId) {
    return _bindings.downloadPause(runtimeId, downloadId);
  }

  int resumeDownload(int runtimeId, int downloadId) {
    return _bindings.downloadResume(runtimeId, downloadId);
  }

  int cancelDownload(int runtimeId, int downloadId) {
    return _bindings.downloadCancel(runtimeId, downloadId);
  }

  Map<String, dynamic> queryAsset(int runtimeId, String mediaId) {
    final mediaPtr = mediaId.toNativeUtf8();
    try {
      final resultPtr = _bindings.queryAsset(runtimeId, mediaPtr);
      final result = resultPtr.toDartString();
      _bindings.freeString(resultPtr);
      return jsonDecode(result) as Map<String, dynamic>;
    } finally {
      calloc.free(mediaPtr);
    }
  }

  List<Map<String, dynamic>> listAssets(
    int runtimeId, {
    Map<String, dynamic> filter = const {},
  }) {
    final filterPtr = jsonEncode(filter).toNativeUtf8();
    try {
      final resultPtr = _bindings.listAssets(runtimeId, filterPtr);
      final result = resultPtr.toDartString();
      _bindings.freeString(resultPtr);
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      return (decoded['items'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);
    } finally {
      calloc.free(filterPtr);
    }
  }

  List<Map<String, dynamic>> listDownloads(
    int runtimeId, {
    Map<String, dynamic> filter = const {},
  }) {
    final filterPtr = jsonEncode(filter).toNativeUtf8();
    try {
      final resultPtr = _bindings.listDownloads(runtimeId, filterPtr);
      final result = resultPtr.toDartString();
      _bindings.freeString(resultPtr);
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      return (decoded['items'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);
    } finally {
      calloc.free(filterPtr);
    }
  }

  int evictAsset(int runtimeId, String assetId) {
    final assetPtr = assetId.toNativeUtf8();
    try {
      return _bindings.evictAsset(runtimeId, assetPtr);
    } finally {
      calloc.free(assetPtr);
    }
  }

  Future<void> dispose() async {
    await _eventController.close();
  }
}
