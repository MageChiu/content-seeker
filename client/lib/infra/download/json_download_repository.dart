import 'dart:convert';
import 'dart:io';

import '../../domain/download/download_status.dart';
import '../../domain/download/download_task_entity.dart';
import '../../platform/storage/app_storage_paths.dart';
import 'download_repository.dart';

class JsonDownloadRepository implements DownloadRepository {
  final AppStoragePaths storagePaths;

  List<DownloadTaskEntity>? _cache;

  JsonDownloadRepository({
    this.storagePaths = const AppStoragePaths(),
  });

  @override
  Future<List<DownloadTaskEntity>> listTasks() async {
    final tasks = await _loadTasks();
    return List<DownloadTaskEntity>.unmodifiable(tasks);
  }

  @override
  Future<void> saveTask(DownloadTaskEntity task) async {
    final tasks = await _loadTasks();
    final index = tasks.indexWhere((item) => item.taskId == task.taskId);
    if (index >= 0) {
      tasks[index] = task;
    } else {
      tasks.add(task);
    }
    await _persist(tasks);
  }

  @override
  Future<void> removeTask(String taskId) async {
    final tasks = await _loadTasks();
    tasks.removeWhere((item) => item.taskId == taskId);
    await _persist(tasks);
  }

  Future<List<DownloadTaskEntity>> _loadTasks() async {
    if (_cache != null) {
      return _cache!;
    }
    final file = await _dataFile();
    if (!await file.exists()) {
      _cache = <DownloadTaskEntity>[];
      return _cache!;
    }
    final raw = await file.readAsString();
    if (raw.trim().isEmpty) {
      _cache = <DownloadTaskEntity>[];
      return _cache!;
    }
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      _cache = <DownloadTaskEntity>[];
      return _cache!;
    }
    _cache = decoded
        .whereType<Map>()
        .map((item) => _decodeTask(Map<String, dynamic>.from(item)))
        .toList(growable: true);
    _cache!.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return _cache!;
  }

  Future<void> _persist(List<DownloadTaskEntity> tasks) async {
    tasks.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final file = await _dataFile();
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(
        tasks.map(_encodeTask).toList(growable: false),
      ),
    );
    _cache = tasks;
  }

  Future<File> _dataFile() {
    return storagePaths.metadataFile('download_tasks.json');
  }

  Map<String, Object?> _encodeTask(DownloadTaskEntity task) {
    return {
      'task_id': task.taskId,
      'media_id': task.mediaId,
      'source_id': task.sourceId,
      'url': task.url.toString(),
      'filename': task.filename,
      'save_path': task.savePath,
      'status': task.status.name,
      'bytes_downloaded': task.bytesDownloaded,
      'total_bytes': task.totalBytes,
      'supports_resume': task.supportsResume,
      'created_at': task.createdAt.toIso8601String(),
      'updated_at': task.updatedAt.toIso8601String(),
      'last_error': task.lastError,
    };
  }

  DownloadTaskEntity _decodeTask(Map<String, dynamic> json) {
    return DownloadTaskEntity(
      taskId: '${json['task_id'] ?? ''}',
      mediaId: '${json['media_id'] ?? ''}',
      sourceId: '${json['source_id'] ?? ''}',
      url: Uri.parse('${json['url'] ?? ''}'),
      filename: '${json['filename'] ?? ''}',
      savePath: '${json['save_path'] ?? ''}',
      status: _parseStatus(json['status']),
      bytesDownloaded: _readInt(json['bytes_downloaded']),
      totalBytes: _readInt(json['total_bytes']),
      supportsResume: json['supports_resume'] == true,
      createdAt: DateTime.tryParse('${json['created_at'] ?? ''}') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: DateTime.tryParse('${json['updated_at'] ?? ''}') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      lastError: _readNullableString(json['last_error']),
    );
  }

  DownloadStatus _parseStatus(Object? value) {
    switch ('$value'.trim().toLowerCase()) {
      case 'resolving':
        return DownloadStatus.resolving;
      case 'running':
        return DownloadStatus.running;
      case 'paused':
        return DownloadStatus.paused;
      case 'completed':
        return DownloadStatus.completed;
      case 'failed':
        return DownloadStatus.failed;
      case 'canceled':
      case 'cancelled':
        return DownloadStatus.canceled;
      default:
        return DownloadStatus.queued;
    }
  }

  int _readInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.round();
    }
    return int.tryParse('$value') ?? 0;
  }

  String? _readNullableString(Object? value) {
    final normalized = '$value'.trim();
    return normalized.isEmpty || normalized == 'null' ? null : normalized;
  }
}
