import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';
import 'package:ffi/ffi.dart';

import 'native_library_loader.dart';
import 'seeker_bindings.dart';

/// 流提取结果
class StreamExtractResult {
  final String url;
  final String title;
  final String quality;
  final String mimeType;
  final String? audioUrl;
  final Map<String, String> headers;

  StreamExtractResult({
    required this.url,
    required this.title,
    required this.quality,
    required this.mimeType,
    this.audioUrl,
    this.headers = const {},
  });

  factory StreamExtractResult.fromJson(Map<String, dynamic> json) {
    return StreamExtractResult(
      url: json['url'] as String? ?? '',
      title: json['title'] as String? ?? '',
      quality: json['quality'] as String? ?? '',
      mimeType: json['mimeType'] as String? ?? '',
      audioUrl: json['audioUrl'] as String?,
      headers: (json['headers'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v.toString())) ??
          const {},
    );
  }
}

/// libseeker 高层封装
/// 提供类型安全的 Dart 接口，隐藏 FFI 细节
class SeekerNative {
  static SeekerNative? _instance;
  late final SeekerBindings _bindings;
  bool _initialized = false;

  SeekerNative._() {
    final lib = loadSeekerLibrary();
    _bindings = SeekerBindings(lib);
  }

  /// 获取单例
  static SeekerNative get instance {
    _instance ??= SeekerNative._();
    return _instance!;
  }

  /// 初始化 libseeker
  void init({String? configJson}) {
    if (_initialized) return;

    final configPtr =
        configJson != null ? configJson.toNativeUtf8() : nullptr;
    try {
      final result = _bindings.init(configPtr.cast());
      if (result != 0) {
        throw StateError('libseeker 初始化失败，错误码: $result');
      }
      _initialized = true;
    } finally {
      if (configPtr != nullptr) {
        calloc.free(configPtr);
      }
    }
  }

  /// 销毁 libseeker
  void destroy() {
    if (!_initialized) return;
    _bindings.destroy();
    _initialized = false;
  }

  /// 获取版本号
  String get version {
    final ptr = _bindings.version();
    return ptr.cast<Utf8>().toDartString();
  }

  /// 是否已初始化
  bool get isInitialized => _initialized && _bindings.isInitialized() == 1;

  /// 获取支持的站点列表
  List<String> get supportedSites {
    final ptr = _bindings.getSupportedSites();
    final jsonStr = ptr.cast<Utf8>().toDartString();
    final list = jsonDecode(jsonStr) as List;
    return list.cast<String>();
  }

  /// 异步提取流地址（通过 Isolate 执行同步 C API，不阻塞 UI）
  Future<StreamExtractResult> extractStream(String url, {String? options}) async {
    if (!_initialized) {
      throw StateError('libseeker 未初始化');
    }

    // 在独立 Isolate 中执行同步 FFI 调用
    final jsonStr = await Isolate.run(() {
      return _extractSync(url, options);
    });

    if (jsonStr == null || jsonStr.isEmpty) {
      throw Exception('原生提取器返回空结果');
    }

    final json = jsonDecode(jsonStr) as Map<String, dynamic>;

    // 检查是否是错误响应
    if (json.containsKey('error')) {
      throw Exception(json['error'] as String);
    }

    return StreamExtractResult.fromJson(json);
  }

  /// 同步提取（在 Isolate 内执行）
  static String? _extractSync(String url, String? options) {
    final lib = loadSeekerLibrary();
    final bindings = SeekerBindings(lib);

    final urlPtr = url.toNativeUtf8();
    final optionsPtr = options != null ? options.toNativeUtf8() : nullptr;

    try {
      final resultPtr = bindings.extractStreamSync(
        urlPtr.cast(),
        optionsPtr.cast(),
      );

      if (resultPtr == nullptr || resultPtr.address == 0) {
        return null;
      }

      final result = resultPtr.cast<Utf8>().toDartString();
      bindings.freeString(resultPtr);
      return result;
    } finally {
      calloc.free(urlPtr);
      if (optionsPtr != nullptr) {
        calloc.free(optionsPtr);
      }
    }
  }

  /// 把 video.m4s + audio.m4s 合成为完整 mp4
  /// macOS/iOS 走 AVFoundation，沙箱友好
  /// 抛 Exception 表示失败
  Future<String> muxAvToMp4({
    required String videoPath,
    String? audioPath,
    required String outputPath,
  }) async {
    if (!_initialized) {
      throw StateError('libseeker 未初始化');
    }
    final jsonStr = await Isolate.run(() {
      return _muxSync(videoPath, audioPath, outputPath);
    });
    if (jsonStr == null || jsonStr.isEmpty) {
      throw Exception('mux 返回空结果');
    }
    final json = jsonDecode(jsonStr) as Map<String, dynamic>;
    if (json.containsKey('error')) {
      throw Exception(json['error'] as String);
    }
    final out = json['output'] as String? ?? outputPath;
    return out;
  }

  /// 在 Isolate 内执行同步 mux
  static String? _muxSync(String video, String? audio, String output) {
    final lib = loadSeekerLibrary();
    final bindings = SeekerBindings(lib);

    final videoPtr = video.toNativeUtf8();
    final audioPtr = audio != null ? audio.toNativeUtf8() : nullptr;
    final outputPtr = output.toNativeUtf8();

    try {
      final resultPtr = bindings.muxAvToMp4(
        videoPtr.cast(),
        audioPtr.cast(),
        outputPtr.cast(),
      );
      if (resultPtr == nullptr || resultPtr.address == 0) {
        return null;
      }
      final result = resultPtr.cast<Utf8>().toDartString();
      bindings.freeString(resultPtr);
      return result;
    } finally {
      calloc.free(videoPtr);
      if (audioPtr != nullptr) {
        calloc.free(audioPtr);
      }
      calloc.free(outputPtr);
    }
  }
}
