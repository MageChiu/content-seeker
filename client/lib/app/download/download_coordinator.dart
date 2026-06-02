import 'package:flutter/foundation.dart';

import '../../domain/download/download_request.dart';
import '../../domain/download/offline_asset.dart';
import '../../domain/download/download_task_entity.dart';
import '../../infra/download/download_engine.dart';
import '../../infra/download/download_repository.dart';
import '../../infra/download/offline_asset_repository.dart';
import '../../infra/download/download_storage_manager.dart';
import 'download_state.dart';

class DownloadCoordinator extends ChangeNotifier {
  final DownloadRepository repository;
  final DownloadStorageManager storageManager;
  final DownloadEngine downloadEngine;
  final OfflineAssetRepository offlineAssetRepository;

  DownloadCoordinator({
    required this.repository,
    required this.storageManager,
    required this.downloadEngine,
    required this.offlineAssetRepository,
  });

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
    replaceState(
      tasks: await repository.listTasks(),
      assets: await offlineAssetRepository.listAssets(),
    );
  }

  Future<DownloadTaskEntity> enqueue(DownloadRequest request) async {
    final storagePlan = await storageManager.planFor(
      sourceId: request.sourceId,
      suggestedFilename: request.filename,
    );
    final task = await downloadEngine.enqueue(
      request: request,
      storagePlan: storagePlan,
    );
    await repository.saveTask(task);
    await loadTasks();
    return task;
  }
}
