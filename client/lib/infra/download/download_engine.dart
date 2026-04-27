import '../../domain/download/download_request.dart';
import '../../domain/download/download_status.dart';
import '../../domain/download/download_task_entity.dart';
import 'download_storage_manager.dart';

abstract class DownloadEngine {
  Future<DownloadTaskEntity> enqueue({
    required DownloadRequest request,
    required DownloadStoragePlan storagePlan,
  });

  Future<DownloadTaskEntity> pause(String taskId);

  Future<DownloadTaskEntity> resume(String taskId);

  Future<DownloadTaskEntity> cancel(String taskId);
}

class NoopDownloadEngine implements DownloadEngine {
  const NoopDownloadEngine();

  @override
  Future<DownloadTaskEntity> enqueue({
    required DownloadRequest request,
    required DownloadStoragePlan storagePlan,
  }) async {
    final now = DateTime.now();
    return DownloadTaskEntity(
      taskId: 'noop-${request.mediaId}-${now.microsecondsSinceEpoch}',
      mediaId: request.mediaId,
      sourceId: request.sourceId,
      url: request.url,
      filename: storagePlan.filename,
      savePath: storagePlan.relativePath,
      status: DownloadStatus.queued,
      createdAt: now,
      updatedAt: now,
      supportsResume: false,
    );
  }

  @override
  Future<DownloadTaskEntity> pause(String taskId) async {
    throw UnimplementedError('NoopDownloadEngine.pause($taskId)');
  }

  @override
  Future<DownloadTaskEntity> resume(String taskId) async {
    throw UnimplementedError('NoopDownloadEngine.resume($taskId)');
  }

  @override
  Future<DownloadTaskEntity> cancel(String taskId) async {
    throw UnimplementedError('NoopDownloadEngine.cancel($taskId)');
  }
}
