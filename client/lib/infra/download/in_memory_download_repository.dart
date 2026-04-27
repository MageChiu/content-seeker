import '../../domain/download/download_task_entity.dart';
import 'download_repository.dart';

class InMemoryDownloadRepository implements DownloadRepository {
  final Map<String, DownloadTaskEntity> _tasks = {};

  @override
  Future<List<DownloadTaskEntity>> listTasks() async {
    return _tasks.values.toList(growable: false);
  }

  @override
  Future<void> saveTask(DownloadTaskEntity task) async {
    _tasks[task.taskId] = task;
  }

  @override
  Future<void> removeTask(String taskId) async {
    _tasks.remove(taskId);
  }
}
