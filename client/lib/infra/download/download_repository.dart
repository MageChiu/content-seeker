import '../../domain/download/download_task_entity.dart';

abstract class DownloadRepository {
  Future<List<DownloadTaskEntity>> listTasks();

  Future<void> saveTask(DownloadTaskEntity task);

  Future<void> removeTask(String taskId);
}
