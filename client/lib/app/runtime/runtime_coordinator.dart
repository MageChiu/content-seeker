import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../app/content/content_request.dart';
import '../../domain/media/download_plan.dart';
import '../../domain/media/media_graph.dart';
import '../../domain/media/materialized_asset.dart';
import '../../domain/runtime/runtime_session_state.dart';
import '../../native_bridge/seeker_runtime_bridge.dart';
import '../../platform/storage/app_storage_paths.dart';
import '../../features/settings/settings_provider.dart';
import 'runtime_config_builder.dart';
import 'runtime_state.dart';

class RuntimeCoordinator extends ChangeNotifier {
  final SeekerRuntimeBridge runtimeBridge;
  final AppStoragePaths storagePaths;
  final SettingsProvider? settingsProvider;

  RuntimeState _state = const RuntimeState();
  StreamSubscription<RuntimeEvent>? _eventSubscription;
  int? _runtimeId;

  RuntimeCoordinator({
    SeekerRuntimeBridge? runtimeBridge,
    AppStoragePaths? storagePaths,
    this.settingsProvider,
  })  : runtimeBridge = runtimeBridge ?? SeekerRuntimeBridge.instance,
        storagePaths = storagePaths ?? const AppStoragePaths() {
    _eventSubscription = this.runtimeBridge.events.listen(_handleRuntimeEvent);
  }

  RuntimeState get state => _state;

  Future<RuntimeSessionState> prepare(ContentRequest request) async {
    final runtimeId = await _ensureRuntime();
    final currentSession = _state.session;
    if (currentSession.runtimeId == runtimeId && currentSession.sessionId > 0) {
      runtimeBridge.disposeSession(runtimeId, currentSession.sessionId);
    }
    final sessionId = runtimeBridge.createSession(runtimeId);
    _state = _state.copyWith(
      initialized: true,
      session: RuntimeSessionState(
        runtimeId: runtimeId,
        sessionId: sessionId,
        status: RuntimeSessionStatus.resolving,
      ),
    );
    notifyListeners();

    final resolved = runtimeBridge.resolveMedia(runtimeId, _buildResolveRequest(request));
    if ('${resolved['error'] ?? ''}'.trim().isNotEmpty) {
      _state = _state.copyWith(
        session: _state.session.copyWith(
          status: RuntimeSessionStatus.failed,
          errorMessage: '${resolved['error']}',
        ),
      );
      notifyListeners();
      throw StateError('${resolved['error']}');
    }

    final mediaGraph = MediaGraph.fromJson(resolved);
    final openResult = runtimeBridge.sessionOpen(runtimeId, sessionId, mediaGraph.toJson());
    if (openResult != 0) {
      _state = _state.copyWith(
        session: _state.session.copyWith(
          status: RuntimeSessionStatus.failed,
          mediaGraph: mediaGraph,
          errorMessage: 'session open failed: $openResult',
        ),
      );
      notifyListeners();
      throw StateError('session open failed: $openResult');
    }

    _state = _state.copyWith(
      session: _state.session.copyWith(
        status: RuntimeSessionStatus.ready,
        mediaGraph: mediaGraph,
        clearError: true,
      ),
    );
    notifyListeners();
    return _state.session;
  }

  Future<void> play() async {
    final session = _state.session;
    if (session.runtimeId <= 0 || session.sessionId <= 0) return;
    runtimeBridge.play(session.runtimeId, session.sessionId);
  }

  Future<void> pause() async {
    final session = _state.session;
    if (session.runtimeId <= 0 || session.sessionId <= 0) return;
    runtimeBridge.pause(session.runtimeId, session.sessionId);
  }

  Future<void> seek(Duration position) async {
    final session = _state.session;
    if (session.runtimeId <= 0 || session.sessionId <= 0) return;
    runtimeBridge.seek(session.runtimeId, session.sessionId, position.inMilliseconds);
  }

  Future<void> setRate(double rate) async {
    final session = _state.session;
    if (session.runtimeId <= 0 || session.sessionId <= 0) return;
    runtimeBridge.setRate(session.runtimeId, session.sessionId, rate);
  }

  Future<void> setVolume(double volume) async {
    final session = _state.session;
    if (session.runtimeId <= 0 || session.sessionId <= 0) return;
    runtimeBridge.setVolume(session.runtimeId, session.sessionId, volume);
  }

  Future<DownloadPlan> buildDownloadPlan({
    String? filename,
  }) async {
    final session = _state.session;
    final mediaGraph = session.mediaGraph;
    if (session.runtimeId <= 0 || mediaGraph == null) {
      throw StateError('runtime session is not ready');
    }
    final plan = runtimeBridge.buildDownloadPlan(
      session.runtimeId,
      mediaGraph.toJson(),
      options: {
        if (filename != null && filename.isNotEmpty) 'filename': filename,
      },
    );
    if ('${plan['error'] ?? ''}'.trim().isNotEmpty) {
      throw StateError('${plan['error']}');
    }
    return DownloadPlan.fromJson(plan);
  }

  Future<int> startDownload({
    String? filename,
  }) async {
    final session = _state.session;
    if (session.runtimeId <= 0) {
      throw StateError('runtime is not initialized');
    }
    final plan = await buildDownloadPlan(filename: filename);
    return runtimeBridge.startDownload(session.runtimeId, plan.toJson());
  }

  Future<MaterializedAsset?> queryCurrentAsset() async {
    final session = _state.session;
    final mediaGraph = session.mediaGraph;
    if (session.runtimeId <= 0 || mediaGraph == null || mediaGraph.mediaId.isEmpty) {
      return null;
    }
    final result = runtimeBridge.queryAsset(session.runtimeId, mediaGraph.mediaId);
    if (result['found'] != true) {
      return null;
    }
    final assetJson = result['asset'];
    if (assetJson is! Map<String, dynamic>) {
      return null;
    }
    return MaterializedAsset.fromJson(assetJson);
  }

  Future<List<MaterializedAsset>> listAssets({
    MaterializedAssetStorageKind? storageKind,
  }) async {
    final runtimeId = _runtimeId;
    if (runtimeId == null || runtimeId <= 0) {
      return const [];
    }
    final items = runtimeBridge.listAssets(
      runtimeId,
      filter: {
        if (storageKind != null) 'storageKind': switch (storageKind) {
          MaterializedAssetStorageKind.temp => 'temp',
          MaterializedAssetStorageKind.cache => 'cache',
          MaterializedAssetStorageKind.offline => 'offline',
        },
      },
    );
    return items.map(MaterializedAsset.fromJson).toList(growable: false);
  }

  Future<void> evictAsset(String assetId) async {
    final runtimeId = _runtimeId;
    if (runtimeId == null || runtimeId <= 0) {
      return;
    }
    runtimeBridge.evictAsset(runtimeId, assetId);
  }

  Future<void> closeCurrentSession() async {
    final session = _state.session;
    if (session.runtimeId > 0 && session.sessionId > 0) {
      runtimeBridge.disposeSession(session.runtimeId, session.sessionId);
    }
    _state = _state.copyWith(
      session: const RuntimeSessionState.idle(),
    );
    notifyListeners();
  }

  Future<int> _ensureRuntime() async {
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

  Map<String, dynamic> _buildResolveRequest(ContentRequest request) {
    final url = (request.primaryUri ?? request.fallbackUri)?.toString() ?? '';
    return {
      'mediaId': request.contentId.isNotEmpty ? request.contentId : request.stableId,
      'sourceId': request.sourceId,
      'title': request.title,
      'url': url,
      'headers': request.headers,
      'filename': request.filename,
      'attributes': request.attributes,
    };
  }

  void _handleRuntimeEvent(RuntimeEvent event) {
    if (event.runtimeId != _state.session.runtimeId ||
        event.sessionId != _state.session.sessionId) {
      return;
    }

    final payload = event.payload;
    final status = _mapStatus(event.type, '${payload['status'] ?? ''}');
    _state = _state.copyWith(
      session: _state.session.copyWith(
        status: status,
        position: Duration(milliseconds: (payload['positionMs'] as num?)?.toInt() ?? 0),
        playbackRate: (payload['rate'] as num?)?.toDouble() ?? _state.session.playbackRate,
        volume: (payload['volume'] as num?)?.toDouble() ?? _state.session.volume,
      ),
    );
    notifyListeners();
  }

  RuntimeSessionStatus _mapStatus(String type, String fallback) {
    switch (type) {
      case 'session.playing':
        return RuntimeSessionStatus.playing;
      case 'session.paused':
        return RuntimeSessionStatus.paused;
      case 'session.ready':
        return RuntimeSessionStatus.ready;
      default:
        switch (fallback) {
          case 'playing':
            return RuntimeSessionStatus.playing;
          case 'paused':
            return RuntimeSessionStatus.paused;
          case 'ready':
            return RuntimeSessionStatus.ready;
          case 'buffering':
            return RuntimeSessionStatus.buffering;
          case 'failed':
            return RuntimeSessionStatus.failed;
          case 'ended':
            return RuntimeSessionStatus.ended;
          case 'resolving':
            return RuntimeSessionStatus.resolving;
          case 'idle':
          default:
            return RuntimeSessionStatus.idle;
        }
    }
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    final runtimeId = _runtimeId;
    if (runtimeId != null && runtimeId > 0) {
      runtimeBridge.destroyRuntime(runtimeId);
    }
    super.dispose();
  }
}
