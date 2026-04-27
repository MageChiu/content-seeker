import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../domain/download/download_request.dart';
import '../../domain/download/download_status.dart';
import '../../domain/download/download_task_entity.dart';
import '../../domain/download/offline_asset.dart';
import 'download_engine.dart';
import 'download_storage_manager.dart';
import 'offline_asset_repository.dart';

class HttpDownloadEngine implements DownloadEngine {
  final http.Client httpClient;
  final OfflineAssetRepository offlineAssetRepository;

  HttpDownloadEngine({
    http.Client? httpClient,
    required this.offlineAssetRepository,
  }) : httpClient = httpClient ?? http.Client();

  @override
  Future<DownloadTaskEntity> enqueue({
    required DownloadRequest request,
    required DownloadStoragePlan storagePlan,
  }) async {
    final now = DateTime.now();
    final taskId = 'download-${request.mediaId}-${now.microsecondsSinceEpoch}';
    final targetDirectory = Directory(storagePlan.absoluteDirectory);
    await targetDirectory.create(recursive: true);
    final targetFile = File(p.join(storagePlan.absoluteDirectory, storagePlan.filename));

    try {
      final streamed = await httpClient.send(
        http.Request('GET', request.url)..headers.addAll(request.headers),
      );
      if (streamed.statusCode >= 400) {
        throw HttpException(
          '下载失败，HTTP ${streamed.statusCode}',
          uri: request.url,
        );
      }

      final sink = targetFile.openWrite();
      var bytesDownloaded = 0;
      await for (final chunk in streamed.stream) {
        bytesDownloaded += chunk.length;
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();

      final fileSize = await targetFile.length();
      await offlineAssetRepository.saveAsset(
        OfflineAsset(
          assetId: 'asset-$taskId',
          mediaId: request.mediaId,
          sourceId: request.sourceId,
          title: request.filename,
          kind: OfflineAssetKind.download,
          localPath: targetFile.path,
          mimeType: _guessMimeType(
            streamed.headers['content-type'],
            targetFile.path,
          ),
          durationMs: 0,
          fileSizeBytes: fileSize,
          contentType: _guessContentType(targetFile.path),
          originalUrl: request.url.toString(),
          createdAt: DateTime.now(),
        ),
      );

      return DownloadTaskEntity(
        taskId: taskId,
        mediaId: request.mediaId,
        sourceId: request.sourceId,
        url: request.url,
        filename: storagePlan.filename,
        savePath: storagePlan.relativePath,
        status: DownloadStatus.completed,
        createdAt: now,
        updatedAt: DateTime.now(),
        bytesDownloaded: bytesDownloaded,
        totalBytes: streamed.contentLength ?? bytesDownloaded,
        supportsResume: false,
      );
    } catch (error) {
      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      return DownloadTaskEntity(
        taskId: taskId,
        mediaId: request.mediaId,
        sourceId: request.sourceId,
        url: request.url,
        filename: storagePlan.filename,
        savePath: storagePlan.relativePath,
        status: DownloadStatus.failed,
        createdAt: now,
        updatedAt: DateTime.now(),
        lastError: error.toString(),
        supportsResume: false,
      );
    }
  }

  @override
  Future<DownloadTaskEntity> pause(String taskId) async {
    throw UnimplementedError('HttpDownloadEngine.pause($taskId)');
  }

  @override
  Future<DownloadTaskEntity> resume(String taskId) async {
    throw UnimplementedError('HttpDownloadEngine.resume($taskId)');
  }

  @override
  Future<DownloadTaskEntity> cancel(String taskId) async {
    throw UnimplementedError('HttpDownloadEngine.cancel($taskId)');
  }

  String _guessMimeType(String? contentTypeHeader, String path) {
    final normalizedHeader = contentTypeHeader?.trim() ?? '';
    if (normalizedHeader.isNotEmpty) {
      return normalizedHeader.split(';').first.trim();
    }
    final lower = path.toLowerCase();
    if (lower.endsWith('.mp3')) return 'audio/mpeg';
    if (lower.endsWith('.m4a')) return 'audio/mp4';
    if (lower.endsWith('.wav')) return 'audio/wav';
    if (lower.endsWith('.flac')) return 'audio/flac';
    if (lower.endsWith('.ogg')) return 'audio/ogg';
    if (lower.endsWith('.mp4')) return 'video/mp4';
    if (lower.endsWith('.webm')) return 'video/webm';
    if (lower.endsWith('.vtt')) return 'text/vtt';
    if (lower.endsWith('.srt')) return 'application/x-subrip';
    if (lower.endsWith('.json')) return 'application/json';
    if (lower.endsWith('.html')) return 'text/html';
    return 'application/octet-stream';
  }

  String _guessContentType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.mp3') ||
        lower.endsWith('.m4a') ||
        lower.endsWith('.wav') ||
        lower.endsWith('.flac') ||
        lower.endsWith('.ogg')) {
      return 'audio';
    }
    if (lower.endsWith('.mp4') || lower.endsWith('.webm')) {
      return 'video';
    }
    if (lower.endsWith('.vtt') || lower.endsWith('.srt')) {
      return 'subtitle';
    }
    if (lower.endsWith('.json') || lower.endsWith('.html')) {
      return 'document';
    }
    return 'binary';
  }
}
