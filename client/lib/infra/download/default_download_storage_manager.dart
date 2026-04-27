import 'package:path/path.dart' as p;

import '../../platform/storage/app_storage_paths.dart';
import 'download_storage_manager.dart';

class DefaultDownloadStorageManager implements DownloadStorageManager {
  final AppStoragePaths storagePaths;

  const DefaultDownloadStorageManager({
    this.storagePaths = const AppStoragePaths(),
  });

  @override
  Future<DownloadStoragePlan> planFor({
    required String sourceId,
    required String suggestedFilename,
  }) async {
    final normalizedSource = sourceId.trim().isEmpty ? 'unknown' : sourceId;
    final normalizedFilename = suggestedFilename.trim().isEmpty
        ? 'download.bin'
        : suggestedFilename.trim();
    final downloadsRoot = await storagePaths.downloadsRoot();
    final relativeDirectory = 'media/downloads/$normalizedSource';
    final absoluteDirectory = p.join(downloadsRoot.path, normalizedSource);

    return DownloadStoragePlan(
      relativeDirectory: relativeDirectory,
      absoluteDirectory: absoluteDirectory,
      filename: normalizedFilename,
    );
  }
}
