import 'dart:ffi';
import 'package:ffi/ffi.dart';

// ===== 函数类型定义 (Native) =====

// 生命周期
typedef SeekerInitNative = Int32 Function(Pointer<Utf8> configJson);
typedef SeekerDestroyNative = Void Function();
typedef SeekerVersionNative = Pointer<Utf8> Function();
typedef SeekerIsInitializedNative = Int32 Function();

// 流提取
typedef SeekerExtractCallbackNative = Void Function(
    Int32 requestId, Pointer<Utf8> resultJson, Pointer<Utf8> error);
typedef SeekerExtractStreamNative = Int32 Function(
    Pointer<Utf8> url,
    Pointer<Utf8> optionsJson,
    Pointer<NativeFunction<SeekerExtractCallbackNative>> callback);
typedef SeekerExtractStreamSyncNative = Pointer<Utf8> Function(
    Pointer<Utf8> url, Pointer<Utf8> optionsJson);
typedef SeekerFreeStringNative = Void Function(Pointer<Utf8> str);
typedef SeekerCancelExtractNative = Void Function(Int32 requestId);
typedef SeekerGetSupportedSitesNative = Pointer<Utf8> Function();

// 音视频合并 (mux)
typedef SeekerMuxAvToMp4Native = Pointer<Utf8> Function(
    Pointer<Utf8> videoPath, Pointer<Utf8> audioPath, Pointer<Utf8> outputPath);

// 播放控制
typedef SeekerPlayerEventCallbackNative = Void Function(
    Int32 playerId, Pointer<Utf8> eventJson);
typedef SeekerPlayerCreateNative = Int32 Function(
    Pointer<NativeFunction<SeekerPlayerEventCallbackNative>> callback);
typedef SeekerPlayerOpenNative = Int32 Function(
    Int32 playerId, Pointer<Utf8> streamJson);
typedef SeekerPlayerPlayNative = Int32 Function(Int32 playerId);
typedef SeekerPlayerPauseNative = Int32 Function(Int32 playerId);
typedef SeekerPlayerSeekNative = Int32 Function(
    Int32 playerId, Double positionSeconds);
typedef SeekerPlayerSetRateNative = Int32 Function(
    Int32 playerId, Double rate);
typedef SeekerPlayerDestroyNative = Void Function(Int32 playerId);

// ===== 函数类型定义 (Dart) =====

typedef SeekerInitDart = int Function(Pointer<Utf8> configJson);
typedef SeekerDestroyDart = void Function();
typedef SeekerVersionDart = Pointer<Utf8> Function();
typedef SeekerIsInitializedDart = int Function();

typedef SeekerExtractStreamDart = int Function(
    Pointer<Utf8> url,
    Pointer<Utf8> optionsJson,
    Pointer<NativeFunction<SeekerExtractCallbackNative>> callback);
typedef SeekerExtractStreamSyncDart = Pointer<Utf8> Function(
    Pointer<Utf8> url, Pointer<Utf8> optionsJson);
typedef SeekerFreeStringDart = void Function(Pointer<Utf8> str);
typedef SeekerCancelExtractDart = void Function(int requestId);
typedef SeekerGetSupportedSitesDart = Pointer<Utf8> Function();

typedef SeekerMuxAvToMp4Dart = Pointer<Utf8> Function(
    Pointer<Utf8> videoPath, Pointer<Utf8> audioPath, Pointer<Utf8> outputPath);

typedef SeekerPlayerCreateDart = int Function(
    Pointer<NativeFunction<SeekerPlayerEventCallbackNative>> callback);
typedef SeekerPlayerOpenDart = int Function(int playerId, Pointer<Utf8> streamJson);
typedef SeekerPlayerPlayDart = int Function(int playerId);
typedef SeekerPlayerPauseDart = int Function(int playerId);
typedef SeekerPlayerSeekDart = int Function(int playerId, double positionSeconds);
typedef SeekerPlayerSetRateDart = int Function(int playerId, double rate);
typedef SeekerPlayerDestroyDart = void Function(int playerId);

/// libseeker 原生函数绑定
/// 直接映射 C API 到 Dart 函数指针
class SeekerBindings {
  final DynamicLibrary _lib;

  late final SeekerInitDart init;
  late final SeekerDestroyDart destroy;
  late final SeekerVersionDart version;
  late final SeekerIsInitializedDart isInitialized;

  late final SeekerExtractStreamDart extractStream;
  late final SeekerExtractStreamSyncDart extractStreamSync;
  late final SeekerFreeStringDart freeString;
  late final SeekerCancelExtractDart cancelExtract;
  late final SeekerGetSupportedSitesDart getSupportedSites;

  late final SeekerMuxAvToMp4Dart muxAvToMp4;

  late final SeekerPlayerCreateDart playerCreate;
  late final SeekerPlayerOpenDart playerOpen;
  late final SeekerPlayerPlayDart playerPlay;
  late final SeekerPlayerPauseDart playerPause;
  late final SeekerPlayerSeekDart playerSeek;
  late final SeekerPlayerSetRateDart playerSetRate;
  late final SeekerPlayerDestroyDart playerDestroy;

  SeekerBindings(this._lib) {
    // 生命周期
    init = _lib.lookupFunction<SeekerInitNative, SeekerInitDart>('seeker_init');
    destroy = _lib.lookupFunction<SeekerDestroyNative, SeekerDestroyDart>(
        'seeker_destroy');
    version = _lib.lookupFunction<SeekerVersionNative, SeekerVersionDart>(
        'seeker_version');
    isInitialized =
        _lib.lookupFunction<SeekerIsInitializedNative, SeekerIsInitializedDart>(
            'seeker_is_initialized');

    // 流提取
    extractStream =
        _lib.lookupFunction<SeekerExtractStreamNative, SeekerExtractStreamDart>(
            'seeker_extract_stream');
    extractStreamSync = _lib.lookupFunction<SeekerExtractStreamSyncNative,
        SeekerExtractStreamSyncDart>('seeker_extract_stream_sync');
    freeString =
        _lib.lookupFunction<SeekerFreeStringNative, SeekerFreeStringDart>(
            'seeker_free_string');
    cancelExtract =
        _lib.lookupFunction<SeekerCancelExtractNative, SeekerCancelExtractDart>(
            'seeker_cancel_extract');
    getSupportedSites = _lib.lookupFunction<SeekerGetSupportedSitesNative,
        SeekerGetSupportedSitesDart>('seeker_get_supported_sites');

    // 音视频合并（容错：如果旧版库未导出该符号，懒加载并在调用时报错）
    try {
      muxAvToMp4 =
          _lib.lookupFunction<SeekerMuxAvToMp4Native, SeekerMuxAvToMp4Dart>(
              'seeker_mux_av_to_mp4');
    } catch (e) {
      muxAvToMp4 = (Pointer<Utf8> v, Pointer<Utf8> a, Pointer<Utf8> o) {
        const msg =
            '{"error":"libseeker 未导出 seeker_mux_av_to_mp4，请重新构建原生库"}';
        return msg.toNativeUtf8();
      };
    }

    // 播放控制
    playerCreate =
        _lib.lookupFunction<SeekerPlayerCreateNative, SeekerPlayerCreateDart>(
            'seeker_player_create');
    playerOpen =
        _lib.lookupFunction<SeekerPlayerOpenNative, SeekerPlayerOpenDart>(
            'seeker_player_open');
    playerPlay =
        _lib.lookupFunction<SeekerPlayerPlayNative, SeekerPlayerPlayDart>(
            'seeker_player_play');
    playerPause =
        _lib.lookupFunction<SeekerPlayerPauseNative, SeekerPlayerPauseDart>(
            'seeker_player_pause');
    playerSeek =
        _lib.lookupFunction<SeekerPlayerSeekNative, SeekerPlayerSeekDart>(
            'seeker_player_seek');
    playerSetRate =
        _lib.lookupFunction<SeekerPlayerSetRateNative, SeekerPlayerSetRateDart>(
            'seeker_player_set_rate');
    playerDestroy =
        _lib.lookupFunction<SeekerPlayerDestroyNative, SeekerPlayerDestroyDart>(
            'seeker_player_destroy');
  }
}
