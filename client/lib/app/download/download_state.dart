import '../../domain/download/download_task_entity.dart';
import '../../domain/download/offline_asset.dart';

class DownloadState {
  final List<DownloadTaskEntity> tasks;
  final List<OfflineAsset> assets;

  const DownloadState({
    this.tasks = const [],
    this.assets = const [],
  });
}
