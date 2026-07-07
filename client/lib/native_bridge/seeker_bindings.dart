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

// runtime / 播放控制
typedef SeekerRuntimeEventCallbackNative = Void Function(
    Int32 runtimeId, Int32 sessionId, Pointer<Utf8> eventJson);
typedef SeekerRuntimeCreateNative = Int32 Function(Pointer<Utf8> configJson);
typedef SeekerRuntimeDestroyNative = Void Function(Int32 runtimeId);
typedef SeekerSessionCreateNative = Int32 Function(
    Int32 runtimeId,
    Pointer<NativeFunction<SeekerRuntimeEventCallbackNative>> callback);
typedef SeekerSessionDisposeNative = Int32 Function(Int32 runtimeId, Int32 sessionId);
typedef SeekerResolveMediaNative = Pointer<Utf8> Function(
    Int32 runtimeId, Pointer<Utf8> requestJson);
typedef SeekerSessionOpenNative = Int32 Function(
    Int32 runtimeId, Int32 sessionId, Pointer<Utf8> resolvedMediaJson);
typedef SeekerSessionPlayNative = Int32 Function(Int32 runtimeId, Int32 sessionId);
typedef SeekerSessionPauseNative = Int32 Function(Int32 runtimeId, Int32 sessionId);
typedef SeekerSessionSeekNative = Int32 Function(
    Int32 runtimeId, Int32 sessionId, Int64 positionMs);
typedef SeekerSessionSetRateNative = Int32 Function(
    Int32 runtimeId, Int32 sessionId, Double rate);
typedef SeekerSessionSetVolumeNative = Int32 Function(
    Int32 runtimeId, Int32 sessionId, Double volume);
typedef SeekerSessionSelectTrackNative = Int32 Function(
    Int32 runtimeId, Int32 sessionId, Pointer<Utf8> trackId);
typedef SeekerSessionSelectVariantNative = Int32 Function(
    Int32 runtimeId, Int32 sessionId, Pointer<Utf8> variantId);
typedef SeekerBuildDownloadPlanNative = Pointer<Utf8> Function(
    Int32 runtimeId, Pointer<Utf8> resolvedMediaJson, Pointer<Utf8> optionsJson);
typedef SeekerDownloadStartNative = Int32 Function(
    Int32 runtimeId, Pointer<Utf8> downloadPlanJson);
typedef SeekerDownloadPauseNative = Int32 Function(Int32 runtimeId, Int32 downloadId);
typedef SeekerDownloadResumeNative = Int32 Function(Int32 runtimeId, Int32 downloadId);
typedef SeekerDownloadCancelNative = Int32 Function(Int32 runtimeId, Int32 downloadId);
typedef SeekerQueryAssetNative = Pointer<Utf8> Function(
    Int32 runtimeId, Pointer<Utf8> mediaId);
typedef SeekerListAssetsNative = Pointer<Utf8> Function(
    Int32 runtimeId, Pointer<Utf8> filterJson);
typedef SeekerListDownloadsNative = Pointer<Utf8> Function(
    Int32 runtimeId, Pointer<Utf8> filterJson);
typedef SeekerEvictAssetNative = Int32 Function(
    Int32 runtimeId, Pointer<Utf8> assetId);

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

typedef SeekerRuntimeCreateDart = int Function(Pointer<Utf8> configJson);
typedef SeekerRuntimeDestroyDart = void Function(int runtimeId);
typedef SeekerSessionCreateDart = int Function(
    int runtimeId,
    Pointer<NativeFunction<SeekerRuntimeEventCallbackNative>> callback);
typedef SeekerSessionDisposeDart = int Function(int runtimeId, int sessionId);
typedef SeekerResolveMediaDart = Pointer<Utf8> Function(
    int runtimeId, Pointer<Utf8> requestJson);
typedef SeekerSessionOpenDart = int Function(
    int runtimeId, int sessionId, Pointer<Utf8> resolvedMediaJson);
typedef SeekerSessionPlayDart = int Function(int runtimeId, int sessionId);
typedef SeekerSessionPauseDart = int Function(int runtimeId, int sessionId);
typedef SeekerSessionSeekDart = int Function(int runtimeId, int sessionId, int positionMs);
typedef SeekerSessionSetRateDart = int Function(int runtimeId, int sessionId, double rate);
typedef SeekerSessionSetVolumeDart = int Function(
    int runtimeId, int sessionId, double volume);
typedef SeekerSessionSelectTrackDart = int Function(
    int runtimeId, int sessionId, Pointer<Utf8> trackId);
typedef SeekerSessionSelectVariantDart = int Function(
    int runtimeId, int sessionId, Pointer<Utf8> variantId);
typedef SeekerBuildDownloadPlanDart = Pointer<Utf8> Function(
    int runtimeId, Pointer<Utf8> resolvedMediaJson, Pointer<Utf8> optionsJson);
typedef SeekerDownloadStartDart = int Function(int runtimeId, Pointer<Utf8> downloadPlanJson);
typedef SeekerDownloadPauseDart = int Function(int runtimeId, int downloadId);
typedef SeekerDownloadResumeDart = int Function(int runtimeId, int downloadId);
typedef SeekerDownloadCancelDart = int Function(int runtimeId, int downloadId);
typedef SeekerQueryAssetDart = Pointer<Utf8> Function(int runtimeId, Pointer<Utf8> mediaId);
typedef SeekerListAssetsDart = Pointer<Utf8> Function(int runtimeId, Pointer<Utf8> filterJson);
typedef SeekerListDownloadsDart = Pointer<Utf8> Function(
    int runtimeId, Pointer<Utf8> filterJson);
typedef SeekerEvictAssetDart = int Function(int runtimeId, Pointer<Utf8> assetId);

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

  late final SeekerRuntimeCreateDart runtimeCreate;
  late final SeekerRuntimeDestroyDart runtimeDestroy;
  late final SeekerSessionCreateDart sessionCreate;
  late final SeekerSessionDisposeDart sessionDispose;
  late final SeekerResolveMediaDart resolveMedia;
  late final SeekerSessionOpenDart sessionOpen;
  late final SeekerSessionPlayDart sessionPlay;
  late final SeekerSessionPauseDart sessionPause;
  late final SeekerSessionSeekDart sessionSeek;
  late final SeekerSessionSetRateDart sessionSetRate;
  late final SeekerSessionSetVolumeDart sessionSetVolume;
  late final SeekerSessionSelectTrackDart sessionSelectTrack;
  late final SeekerSessionSelectVariantDart sessionSelectVariant;
  late final SeekerBuildDownloadPlanDart buildDownloadPlan;
  late final SeekerDownloadStartDart downloadStart;
  late final SeekerDownloadPauseDart downloadPause;
  late final SeekerDownloadResumeDart downloadResume;
  late final SeekerDownloadCancelDart downloadCancel;
  late final SeekerQueryAssetDart queryAsset;
  late final SeekerListAssetsDart listAssets;
  late final SeekerListDownloadsDart listDownloads;
  late final SeekerEvictAssetDart evictAsset;

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

    // runtime / 播放控制
    runtimeCreate =
        _lib.lookupFunction<SeekerRuntimeCreateNative, SeekerRuntimeCreateDart>(
            'seeker_runtime_create');
    runtimeDestroy = _lib
        .lookupFunction<SeekerRuntimeDestroyNative, SeekerRuntimeDestroyDart>(
            'seeker_runtime_destroy');
    sessionCreate =
        _lib.lookupFunction<SeekerSessionCreateNative, SeekerSessionCreateDart>(
            'seeker_session_create');
    sessionDispose = _lib.lookupFunction<SeekerSessionDisposeNative,
        SeekerSessionDisposeDart>('seeker_session_dispose');
    resolveMedia =
        _lib.lookupFunction<SeekerResolveMediaNative, SeekerResolveMediaDart>(
            'seeker_resolve_media');
    sessionOpen =
        _lib.lookupFunction<SeekerSessionOpenNative, SeekerSessionOpenDart>(
            'seeker_session_open');
    sessionPlay =
        _lib.lookupFunction<SeekerSessionPlayNative, SeekerSessionPlayDart>(
            'seeker_session_play');
    sessionPause =
        _lib.lookupFunction<SeekerSessionPauseNative, SeekerSessionPauseDart>(
            'seeker_session_pause');
    sessionSeek =
        _lib.lookupFunction<SeekerSessionSeekNative, SeekerSessionSeekDart>(
            'seeker_session_seek');
    sessionSetRate = _lib.lookupFunction<SeekerSessionSetRateNative,
        SeekerSessionSetRateDart>('seeker_session_set_rate');
    sessionSetVolume = _lib.lookupFunction<SeekerSessionSetVolumeNative,
        SeekerSessionSetVolumeDart>('seeker_session_set_volume');
    sessionSelectTrack = _lib.lookupFunction<SeekerSessionSelectTrackNative,
        SeekerSessionSelectTrackDart>('seeker_session_select_track');
    sessionSelectVariant = _lib.lookupFunction<SeekerSessionSelectVariantNative,
        SeekerSessionSelectVariantDart>('seeker_session_select_variant');
    buildDownloadPlan = _lib.lookupFunction<SeekerBuildDownloadPlanNative,
        SeekerBuildDownloadPlanDart>('seeker_build_download_plan');
    downloadStart = _lib.lookupFunction<SeekerDownloadStartNative,
        SeekerDownloadStartDart>('seeker_download_start');
    downloadPause = _lib.lookupFunction<SeekerDownloadPauseNative,
        SeekerDownloadPauseDart>('seeker_download_pause');
    downloadResume = _lib.lookupFunction<SeekerDownloadResumeNative,
        SeekerDownloadResumeDart>('seeker_download_resume');
    downloadCancel = _lib.lookupFunction<SeekerDownloadCancelNative,
        SeekerDownloadCancelDart>('seeker_download_cancel');
    queryAsset =
        _lib.lookupFunction<SeekerQueryAssetNative, SeekerQueryAssetDart>(
            'seeker_query_asset');
    listAssets =
        _lib.lookupFunction<SeekerListAssetsNative, SeekerListAssetsDart>(
            'seeker_list_assets');
    listDownloads = _lib.lookupFunction<SeekerListDownloadsNative,
        SeekerListDownloadsDart>('seeker_list_downloads');
    evictAsset =
        _lib.lookupFunction<SeekerEvictAssetNative, SeekerEvictAssetDart>(
            'seeker_evict_asset');
  }
}
