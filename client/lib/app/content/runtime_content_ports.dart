import '../../domain/download/download_task_entity.dart';
import '../../domain/media/playback_session.dart';
import '../../domain/media/resolved_media.dart';
import '../../domain/media/source_capability.dart';
import '../../native_bridge/seeker_runtime_bridge.dart';
import '../../platform/storage/app_storage_paths.dart';
import '../../features/settings/settings_provider.dart';
import '../download/download_coordinator.dart';
import '../runtime/runtime_config_builder.dart';
import 'content_bridge.dart';
import 'content_ports.dart';
import 'content_request.dart';

class RuntimeContentPlaybackPort implements ContentPlaybackPort {
  final SeekerRuntimeBridge runtimeBridge;
  final AppStoragePaths storagePaths;
  final SettingsProvider? settingsProvider;
  int? _runtimeId;

  RuntimeContentPlaybackPort({
    SeekerRuntimeBridge? runtimeBridge,
    AppStoragePaths? storagePaths,
    this.settingsProvider,
  })  : runtimeBridge = runtimeBridge ?? SeekerRuntimeBridge.instance,
        storagePaths = storagePaths ?? const AppStoragePaths();

  @override
  Future<PlaybackSession> prepare(ContentRequest request) async {
    final runtimeId = await _ensureRuntimeAsync();
    final sessionId = runtimeBridge.createSession(runtimeId);
    final result = runtimeBridge.resolveMedia(runtimeId, {
      'mediaId': request.contentId.isNotEmpty ? request.contentId : request.stableId,
      'sourceId': request.sourceId,
      'title': request.title,
      'url': (request.primaryUri ?? request.fallbackUri)?.toString() ?? '',
      'headers': request.headers,
      'filename': request.filename,
      'attributes': request.attributes,
    });
    if ('${result['error'] ?? ''}'.trim().isNotEmpty) {
      throw StateError('${result['error']}');
    }
    final openCode = runtimeBridge.sessionOpen(runtimeId, sessionId, result);
    if (openCode != 0) {
      throw StateError('runtime session open failed: $openCode');
    }
    final media = _mapResolvedMedia(result);
    return PlaybackSession(
      sessionId: '$runtimeId:$sessionId',
      mediaId: media.title.isNotEmpty ? media.title : (request.contentId.isNotEmpty ? request.contentId : request.stableId),
      media: media,
    );
  }

  Future<int> _ensureRuntimeAsync() async {
    final existing = _runtimeId;
    if (existing != null && existing > 0) {
      return existing;
    }
    final root = await storagePaths.appSupportRoot();
    final runtimeId = runtimeBridge.createRuntime(
      config: buildRuntimeConfig(
        appSupportRoot: root.path,
        storagePolicy: settingsProvider?.runtimeStoragePolicy,
      ),
    );
    _runtimeId = runtimeId;
    return runtimeId;
  }

  ResolvedMedia _mapResolvedMedia(Map<String, dynamic> json) {
    final primary = Uri.parse('${json['primaryUrl'] ?? ''}');
    final secondary = _optionalUri(json['secondaryAudioUrl']);
    final inputUrl = _optionalUri(json['inputUrl']);
    final fallbacks = (json['fallbacks'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .map((item) => FallbackCandidate(
              kind: ResolvedMediaKind.external,
              uri: Uri.tryParse('${item['url'] ?? ''}') ?? primary,
              label: '${item['label'] ?? ''}',
            ))
        .toList(growable: false);

    return ResolvedMedia(
      sourceId: '${json['sourceId'] ?? ''}',
      kind: ResolvedMediaKind.nativeStream,
      primaryUri: primary,
      secondaryAudioUri: secondary,
      headers: (json['auth'] as Map<String, dynamic>? ?? const {})['headers'] is Map
          ? Map<String, String>.from(
              ((json['auth'] as Map<String, dynamic>)['headers'] as Map)
                  .map((key, value) => MapEntry('$key', '$value')),
            )
          : const {},
      fallbacks: [
        ...fallbacks,
        if (inputUrl != null && inputUrl != primary)
          FallbackCandidate(kind: ResolvedMediaKind.external, uri: inputUrl, label: 'input'),
      ],
      capability: const SourceCapability(
        supportsDownload: true,
        supportsOffline: true,
        supportsProgressiveCache: true,
      ),
      title: '${json['title'] ?? ''}',
      displayLabel: '${json['displayLabel'] ?? ''}',
      mimeType: '${json['mimeType'] ?? ''}',
    );
  }

  Uri? _optionalUri(Object? value) {
    final text = '$value'.trim();
    if (text.isEmpty || text == 'null') {
      return null;
    }
    return Uri.tryParse(text);
  }
}

class RuntimeContentDownloadPort implements ContentDownloadPort {
  final DownloadCoordinator downloadCoordinator;

  RuntimeContentDownloadPort({
    required this.downloadCoordinator,
  });

  @override
  Future<DownloadTaskEntity> enqueue(ContentRequest request) {
    final uri = request.primaryUri ?? request.fallbackUri;
    if (uri == null) {
      throw StateError('当前内容缺少可下载地址。');
    }
    return downloadCoordinator.enqueue(
      request.toLegacyDownloadRequest(),
    );
  }
}
