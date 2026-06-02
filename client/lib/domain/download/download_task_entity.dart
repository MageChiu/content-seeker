import 'download_status.dart';

class DownloadTaskEntity {
  final String taskId;
  final String mediaId;
  final String sourceId;
  final Uri url;
  final String filename;
  final String savePath;
  final DownloadStatus status;
  final int bytesDownloaded;
  final int totalBytes;
  final bool supportsResume;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? lastError;

  const DownloadTaskEntity({
    required this.taskId,
    required this.mediaId,
    required this.sourceId,
    required this.url,
    required this.filename,
    required this.savePath,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.bytesDownloaded = 0,
    this.totalBytes = 0,
    this.supportsResume = false,
    this.lastError,
  });
}
