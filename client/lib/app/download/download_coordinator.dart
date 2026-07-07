import 'package:flutter/foundation.dart';

import '../../app/content/content_bridge.dart';
import '../../app/content/content_request.dart';
import '../../domain/download/download_status.dart';
import '../../domain/download/download_request.dart';
import '../../domain/download/offline_asset.dart';
import '../../domain/download/download_task_entity.dart';
import '../../native_bridge/seeker_runtime_bridge.dart';
import '../../platform/storage/app_storage_paths.dart';
import '../../features/settings/settings_provider.dart';
import '../runtime/runtime_config_builder.dart';
import 'download_state.dart';

class DownloadCoordinator extends ChangeNotifier {
  final SeekerRuntimeBridge runtimeBridge;
  final AppStoragePaths storagePaths;
  final SettingsProvider? settingsProvider;
  int? _runtimeId;

  DownloadCoordinator({
    SeekerRuntimeBridge? runtimeBridge,
    AppStoragePaths? storagePaths,
    this.settingsProvider,
  })  : runtimeBridge = runtimeBridge ?? SeekerRuntimeBridge.instance,
        storagePaths = storagePaths ?? const AppStoragePaths();

  DownloadState _state = const DownloadState();

  DownloadState get state => _state;

  void replaceState({
    required List<DownloadTaskEntity> tasks,
    required List<OfflineAsset> assets,
  }) {
    _state = DownloadState(
      tasks: List.unmodifiable(tasks),
      assets: List.unmodifiable(assets),
    );
    notifyListeners();
  }

  Future<void> loadTasks() async {
    final runtimeId = await _ensureRuntime();
    replaceState(
      tasks: runtimeBridge
          .listDownloads(runtimeId)
          .map(_mapRuntimeDownload)
          .toList(growable: false),
      assets: runtimeBridge
          .listAssets(runtimeId)
          .map(_mapRuntimeAsset)
          .toList(growable: false),
    );
  }

  Future<DownloadTaskEntity> enqueue(DownloadRequest request) async {
    final runtimeId = await _ensureRuntime();
    final content = request.toContentRequest().copyWith(
      intent: ContentIntent.download,
    );
    final resolveResult = runtimeBridge.resolveMedia(
      runtimeId,
      {
        'mediaId': content.contentId.isNotEmpty ? content.contentId : content.stableId,
        'sourceId': content.sourceId,
        'title': content.title,
        'url': (content.primaryUri ?? content.fallbackUri)?.toString() ?? '',
        'headers': content.headers,
        'filename': content.filename,
        'attributes': content.attributes,
      },
    );
    if ('${resolveResult['error'] ?? ''}'.trim().isNotEmpty) {
      throw StateError('${resolveResult['error']}');
    }
    final plan = runtimeBridge.buildDownloadPlan(
      runtimeId,
      resolveResult,
      options: {
        if (request.filename.trim().isNotEmpty) 'filename': request.filename.trim(),
      },
    );
    if ('${plan['error'] ?? ''}'.trim().isNotEmpty) {
      throw StateError('${plan['error']}');
    }
    final downloadId = runtimeBridge.startDownload(runtimeId, plan);
    if (downloadId <= 0) {
      throw StateError('启动下载失败: $downloadId');
    }
    await loadTasks();
    return _state.tasks.firstWhere(
      (task) => task.taskId == 'runtime-download-$downloadId',
      orElse: () => DownloadTaskEntity(
        taskId: 'runtime-download-$downloadId',
        mediaId: request.mediaId,
        sourceId: request.sourceId,
        url: request.url,
        filename: request.filename,
        savePath: plan['savePath']?.toString() ?? request.filename,
        status: DownloadStatus.running,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        supportsResume: true,
      ),
    );
  }

  Future<void> pauseTask(DownloadTaskEntity task) async {
    final runtimeId = await _ensureRuntime();
    final downloadId = _parseDownloadId(task.taskId);
    if (downloadId == null) return;
    runtimeBridge.pauseDownload(runtimeId, downloadId);
    await loadTasks();
  }

  Future<void> resumeTask(DownloadTaskEntity task) async {
    final runtimeId = await _ensureRuntime();
    final downloadId = _parseDownloadId(task.taskId);
    if (downloadId == null) return;
    runtimeBridge.resumeDownload(runtimeId, downloadId);
    await loadTasks();
  }

  Future<void> cancelTask(DownloadTaskEntity task) async {
    final runtimeId = await _ensureRuntime();
    final downloadId = _parseDownloadId(task.taskId);
    if (downloadId == null) return;
    runtimeBridge.cancelDownload(runtimeId, downloadId);
    await loadTasks();
  }

  Future<void> evictAsset(OfflineAsset asset) async {
    final runtimeId = await _ensureRuntime();
    if (asset.assetId.trim().isEmpty) return;
    runtimeBridge.evictAsset(runtimeId, asset.assetId);
    await loadTasks();
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

  DownloadTaskEntity _mapRuntimeDownload(Map<String, dynamic> json) {
    final url = Uri.tryParse('${json['primaryUrl'] ?? ''}') ?? Uri();
    return DownloadTaskEntity(
      taskId: '${json['taskId'] ?? ''}',
      mediaId: '${json['mediaId'] ?? ''}',
      sourceId: '${json['sourceId'] ?? ''}',
      url: url,
      filename: '${json['filename'] ?? ''}',
      savePath: '${json['savePath'] ?? ''}',
      status: _mapDownloadStatus('${json['status'] ?? ''}'),
      bytesDownloaded: (json['bytesDownloaded'] as num?)?.toInt() ?? 0,
      totalBytes: (json['totalBytes'] as num?)?.toInt() ?? 0,
      supportsResume: json['supportsResume'] != false,
      createdAt: DateTime.tryParse('${json['createdAt'] ?? ''}') ?? DateTime.now(),
      updatedAt: DateTime.tryParse('${json['updatedAt'] ?? ''}') ?? DateTime.now(),
      lastError: '${json['lastError'] ?? ''}'.trim().isEmpty
          ? null
          : '${json['lastError']}',
    );
  }

  OfflineAsset _mapRuntimeAsset(Map<String, dynamic> json) {
    final mimeType = '${json['mimeType'] ?? ''}';
    return OfflineAsset(
      assetId: '${json['assetId'] ?? ''}',
      mediaId: '${json['mediaId'] ?? ''}',
      sourceId: '${json['sourceId'] ?? ''}',
      title: '${json['title'] ?? ''}',
      kind: OfflineAssetKind.download,
      localPath: '${json['primaryFilePath'] ?? ''}',
      mimeType: mimeType,
      durationMs: 0,
      fileSizeBytes: (json['bytesReady'] as num?)?.toInt() ?? 0,
      contentType: _inferContentType(mimeType),
      originalUrl: '',
      createdAt: DateTime.tryParse('${json['createdAt'] ?? ''}') ?? DateTime.now(),
    );
  }

  DownloadStatus _mapDownloadStatus(String value) {
    switch (value) {
      case 'running':
        return DownloadStatus.running;
      case 'paused':
        return DownloadStatus.paused;
      case 'completed':
        return DownloadStatus.completed;
      case 'failed':
        return DownloadStatus.failed;
      case 'canceled':
        return DownloadStatus.canceled;
      case 'resolving':
        return DownloadStatus.resolving;
      case 'queued':
      default:
        return DownloadStatus.queued;
    }
  }

  String _inferContentType(String mimeType) {
    if (mimeType.startsWith('audio/')) {
      return 'audio';
    }
    if (mimeType.startsWith('video/')) {
      return 'video';
    }
    return '';
  }

  int? _parseDownloadId(String taskId) {
    final match = RegExp(r'runtime-download-(\d+)$').firstMatch(taskId.trim());
    return int.tryParse(match?.group(1) ?? '');
  }

  @override
  void dispose() {
    final runtimeId = _runtimeId;
    if (runtimeId != null && runtimeId > 0) {
      runtimeBridge.destroyRuntime(runtimeId);
    }
    super.dispose();
  }
}
