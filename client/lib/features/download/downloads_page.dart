import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/download/download_coordinator.dart';
import '../../domain/download/download_status.dart';
import '../../domain/download/offline_asset.dart';

class DownloadsPage extends StatefulWidget {
  const DownloadsPage({super.key});

  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      context.read<DownloadCoordinator>().loadTasks();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('下载与离线资产'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: () => context.read<DownloadCoordinator>().loadTasks(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Consumer<DownloadCoordinator>(
        builder: (context, coordinator, _) {
          final tasks = coordinator.state.tasks;
          final assets = coordinator.state.assets;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                '下载任务',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              if (tasks.isEmpty)
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.download_outlined),
                    title: Text('还没有下载任务'),
                    subtitle: Text('从搜索结果卡片发起下载后，这里会展示真实落盘结果。'),
                  ),
                ),
              for (final task in tasks) ...[
                Card(
                  child: ListTile(
                    leading: Icon(_statusIcon(task.status)),
                    title: Text(task.filename),
                    subtitle: Text(
                      '${task.sourceId} · ${task.status.name} · ${task.savePath}',
                    ),
                    isThreeLine: true,
                    trailing: Wrap(
                      spacing: 4,
                      children: [
                        if (task.status == DownloadStatus.running)
                          IconButton(
                            tooltip: '暂停',
                            onPressed: () => context
                                .read<DownloadCoordinator>()
                                .pauseTask(task),
                            icon: const Icon(Icons.pause_circle_outline),
                          ),
                        if (task.status == DownloadStatus.paused)
                          IconButton(
                            tooltip: '恢复',
                            onPressed: () => context
                                .read<DownloadCoordinator>()
                                .resumeTask(task),
                            icon: const Icon(Icons.play_circle_outline),
                          ),
                        if (task.status != DownloadStatus.completed &&
                            task.status != DownloadStatus.canceled)
                          IconButton(
                            tooltip: '取消',
                            onPressed: () => context
                                .read<DownloadCoordinator>()
                                .cancelTask(task),
                            icon: const Icon(Icons.cancel_outlined),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 20),
              Text(
                '离线资产',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              if (assets.isEmpty)
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.inventory_2_outlined),
                    title: Text('还没有离线资产'),
                    subtitle: Text('保存阅读内容或下载媒体文件后，这里会登记对应的离线资产。'),
                  ),
                ),
              for (final asset in assets) ...[
                Card(
                  child: ListTile(
                    leading: Icon(_assetIcon(asset)),
                    title: Text(asset.title),
                    subtitle: Text(
                      '${asset.kind == OfflineAssetKind.snapshot ? '快照' : '下载'} · ${asset.contentType.isEmpty ? asset.mimeType : asset.contentType} · ${asset.localPath}',
                    ),
                    isThreeLine: true,
                    trailing: IconButton(
                      tooltip: '移除资产',
                      onPressed: () =>
                          context.read<DownloadCoordinator>().evictAsset(asset),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ],
          );
        },
      ),
    );
  }

  IconData _statusIcon(DownloadStatus status) {
    switch (status) {
      case DownloadStatus.completed:
        return Icons.check_circle_outline;
      case DownloadStatus.failed:
        return Icons.error_outline;
      case DownloadStatus.running:
      case DownloadStatus.resolving:
        return Icons.downloading_outlined;
      case DownloadStatus.paused:
        return Icons.pause_circle_outline;
      case DownloadStatus.canceled:
        return Icons.cancel_outlined;
      case DownloadStatus.queued:
        return Icons.schedule_outlined;
    }
  }

  IconData _assetIcon(OfflineAsset asset) {
    if (asset.kind == OfflineAssetKind.snapshot) {
      return Icons.bookmark_added_outlined;
    }
    if (asset.contentType == 'audio') {
      return Icons.music_note_outlined;
    }
    if (asset.contentType == 'video') {
      return Icons.video_library_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }
}
