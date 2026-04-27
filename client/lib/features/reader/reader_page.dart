import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/download/download_coordinator.dart';
import '../../core/content/content.dart';
import '../../domain/download/download_request.dart';
import '../../domain/download/download_status.dart';
import 'reader_provider.dart';

class ReaderPage extends StatelessWidget {
  const ReaderPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('阅读'),
          bottom: const TabBar(
            tabs: [
              Tab(text: '发现'),
              Tab(text: '书架'),
              Tab(text: '订阅'),
            ],
          ),
          actions: [
            IconButton(
              tooltip: '刷新',
              onPressed: () => context.read<ReaderProvider>().refresh(),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: Consumer<ReaderProvider>(
          builder: (context, provider, _) {
            return Column(
              children: [
                _ReaderSummary(provider: provider),
                if (provider.error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Material(
                      color: Theme.of(context)
                          .colorScheme
                          .errorContainer
                          .withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline),
                            const SizedBox(width: 8),
                            Expanded(child: Text(provider.error!)),
                          ],
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: Stack(
                    children: [
                      const TabBarView(
                        children: [
                          _DiscoverTab(),
                          _LibraryTab(),
                          _SubscriptionTab(),
                        ],
                      ),
                      if (provider.loading)
                        const Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: LinearProgressIndicator(),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ReaderSummary extends StatelessWidget {
  final ReaderProvider provider;

  const _ReaderSummary({required this.provider});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          Chip(
            avatar: const Icon(Icons.auto_stories_outlined, size: 18),
            label: Text('内容源 ${provider.featuredItems.length}'),
          ),
          Chip(
            avatar: const Icon(Icons.bookmark_outline, size: 18),
            label: Text('书架 ${provider.libraryEntries.length}'),
          ),
          Chip(
            avatar: const Icon(Icons.rss_feed_outlined, size: 18),
            label: Text('活跃订阅 ${provider.activeSubscriptionCount}'),
          ),
          Chip(
            backgroundColor: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.8),
            label: const Text('真实源: DEV.to / Google News RSS / 精选 RSS'),
          ),
        ],
      ),
    );
  }
}

class _DiscoverTab extends StatelessWidget {
  const _DiscoverTab();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ReaderProvider>();
    final sourceLabels = provider.featuredItems
        .map((entity) => entity.handle.source.displayName)
        .toSet()
        .toList(growable: false);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        Text(
          '已接入内容源',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final label in sourceLabels)
              Chip(
                avatar: const Icon(Icons.extension_outlined, size: 18),
                label: Text(label),
              ),
          ],
        ),
        const SizedBox(height: 16),
        for (final entity in provider.featuredItems) ...[
          _ReaderCard(entity: entity),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _LibraryTab extends StatelessWidget {
  const _LibraryTab();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ReaderProvider>();
    if (provider.libraryEntries.isEmpty) {
      return const _EmptyState(
        icon: Icons.bookmarks_outlined,
        title: '书架还是空的',
        subtitle: '在发现页保存任意阅读内容后，这里会展示阅读记录。',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: provider.libraryEntries.length,
      itemBuilder: (context, index) {
        final entry = provider.libraryEntries[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Card(
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              title: Text(entry.entity.title),
              subtitle: Text(
                '${entry.entity.subtitle}\n已保存为 ${_saveModeLabel(entry.mode)}',
              ),
              isThreeLine: true,
              trailing: IconButton(
                tooltip: '移出书架',
                onPressed: () async {
                  await context
                      .read<ReaderProvider>()
                      .removeSaved(entry.entryId);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已从书架移除')),
                    );
                  }
                },
                icon: const Icon(Icons.delete_outline),
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ReaderDetailPage(handle: entry.entity.handle),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SubscriptionTab extends StatelessWidget {
  const _SubscriptionTab();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ReaderProvider>();
    if (provider.subscriptions.isEmpty) {
      return const _EmptyState(
        icon: Icons.rss_feed_outlined,
        title: '还没有订阅内容',
        subtitle: 'RSS 和小说示例支持订阅，点击卡片上的订阅按钮即可出现在这里。',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: provider.subscriptions.length,
      itemBuilder: (context, index) {
        final record = provider.subscriptions[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Card(
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              title: Text(record.entity?.title ?? record.handle.id),
              subtitle: Text('状态: ${_subscriptionStateLabel(record.state)}'),
              leading: CircleAvatar(
                child: Icon(
                  record.state == ContentSubscriptionState.active
                      ? Icons.notifications_active_outlined
                      : Icons.notifications_paused_outlined,
                ),
              ),
              trailing: IconButton(
                tooltip: '取消订阅',
                onPressed: () async {
                  await context
                      .read<ReaderProvider>()
                      .unsubscribe(record.subscriptionId);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已取消订阅')),
                    );
                  }
                },
                icon: const Icon(Icons.close),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ReaderCard extends StatelessWidget {
  final ContentEntity entity;

  const _ReaderCard({required this.entity});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ReaderProvider>();
    final theme = Theme.of(context);
    final saved = provider.isSaved(entity.handle);
    final subscription = provider.subscriptionForHandle(entity.handle);
    final metadataLabel = _metadataLabel(entity);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 22,
                  child: Icon(_readerIcon(entity)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entity.title,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        entity.subtitle,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(entity.summary),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text(entity.handle.source.displayName)),
                Chip(label: Text(_readerKindLabel(entity))),
                if (metadataLabel != null) Chip(label: Text(metadataLabel)),
                if (saved) const Chip(label: Text('已保存')),
                if (subscription != null)
                  Chip(
                    label: Text(
                      '订阅:${_subscriptionStateLabel(subscription.state)}',
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ReaderDetailPage(handle: entity.handle),
                    ),
                  ),
                  icon: const Icon(Icons.chrome_reader_mode_outlined),
                  label: const Text('阅读'),
                ),
                FilledButton.icon(
                  onPressed: () async {
                    await context.read<ReaderProvider>().save(entity);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('已离线保存: ${entity.title}')),
                      );
                    }
                  },
                  icon: const Icon(Icons.bookmark_add_outlined),
                  label: const Text('离线保存'),
                ),
                if (_canDownload(entity))
                  OutlinedButton.icon(
                    onPressed: () => _downloadEntity(context, entity),
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('下载'),
                  ),
                if (entity.supports(ContentCapability.subscribe))
                  OutlinedButton.icon(
                    onPressed: () async {
                      final record = await context
                          .read<ReaderProvider>()
                          .toggleSubscription(entity.handle);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              '订阅状态已更新为 ${_subscriptionStateLabel(record.state)}',
                            ),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.rss_feed_outlined),
                    label: const Text('订阅'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ReaderDetailPage extends StatelessWidget {
  final ContentHandle handle;

  const ReaderDetailPage({
    super.key,
    required this.handle,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.read<ReaderProvider>();
    return FutureBuilder<ContentDetail>(
      future: provider.loadDetail(handle),
      builder: (context, snapshot) {
        final detail = snapshot.data;
        final title = detail?.entity.title ?? '阅读详情';
        return Scaffold(
          appBar: AppBar(
            title: Text(title),
            actions: [
              if (detail != null)
                IconButton(
                  tooltip: '离线保存',
                  onPressed: () async {
                    await context.read<ReaderProvider>().saveDetail(detail);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('已离线保存: ${detail.entity.title}')),
                      );
                    }
                  },
                  icon: const Icon(Icons.bookmark_add_outlined),
                ),
              if (detail != null && _canDownload(detail.entity))
                IconButton(
                  tooltip: '下载',
                  onPressed: () => _downloadEntity(context, detail.entity),
                  icon: const Icon(Icons.download_outlined),
                ),
              if (detail != null && detail.entity.supports(ContentCapability.open))
                IconButton(
                  tooltip: '打开原文',
                  onPressed: () => _openOriginal(context, detail.entity.handle),
                  icon: const Icon(Icons.open_in_browser),
                ),
            ],
          ),
          body: Builder(
            builder: (context) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError || detail == null) {
                return Center(
                  child: Text('内容加载失败: ${snapshot.error ?? '未知错误'}'),
                );
              }
              return _ReaderDetailBody(detail: detail);
            },
          ),
        );
      },
    );
  }

  Future<void> _openOriginal(BuildContext context, ContentHandle handle) async {
    final provider = context.read<ReaderProvider>();
    final target = await provider.resolveOpenTarget(handle);
    final ok =
        await launchUrl(target.target, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法打开原文链接')),
      );
    }
  }
}

bool _canDownload(ContentEntity entity) {
  if (!entity.supports(ContentCapability.download)) {
    return false;
  }
  return _downloadUrlForEntity(entity) != null;
}

String? _downloadUrlForEntity(ContentEntity entity) {
  final raw = '${entity.metadata['legacy.playUrl'] ?? ''}'.trim();
  if (raw.isNotEmpty) {
    return raw;
  }
  final canonical = entity.canonicalUri?.toString().trim() ?? '';
  return canonical.isEmpty ? null : canonical;
}

String _downloadFilenameForEntity(ContentEntity entity, Uri uri) {
  final safeTitle = entity.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  final base = safeTitle.isEmpty ? entity.handle.id : safeTitle;
  final last = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
  final dotIndex = last.lastIndexOf('.');
  if (dotIndex > 0 && dotIndex < last.length - 1) {
    return '$base.${last.substring(dotIndex + 1)}';
  }
  return base;
}

Future<void> _downloadEntity(BuildContext context, ContentEntity entity) async {
  final rawUrl = _downloadUrlForEntity(entity);
  final uri = rawUrl == null ? null : Uri.tryParse(rawUrl);
  if (uri == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('当前内容没有可下载地址')),
    );
    return;
  }

  try {
    final task = await context.read<DownloadCoordinator>().enqueue(
          DownloadRequest(
            mediaId: entity.handle.stableId,
            sourceId: entity.handle.source.sourceId,
            url: uri,
            filename: _downloadFilenameForEntity(entity, uri),
          ),
        );
    if (context.mounted) {
      final statusLabel =
          task.status == DownloadStatus.completed ? '已下载' : task.status.name;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$statusLabel: ${task.filename}')),
      );
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('下载失败: $error')),
      );
    }
  }
}

class _ReaderDetailBody extends StatelessWidget {
  final ContentDetail detail;

  const _ReaderDetailBody({required this.detail});

  @override
  Widget build(BuildContext context) {
    final entity = detail.entity;
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          entity.title,
          style: theme.textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          entity.summary,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Chip(label: Text(entity.handle.source.displayName)),
            Chip(label: Text(_readerKindLabel(entity))),
            if (entity.metadata['author'] != null)
              Chip(label: Text('作者 ${entity.metadata['author']}')),
          ],
        ),
        const SizedBox(height: 16),
        if (detail.description.isNotEmpty) Text(detail.description),
        const SizedBox(height: 16),
        ...switch (entity.readerKind) {
          ContentReaderKind.webArticle => _buildArticleSections(detail),
          ContentReaderKind.rss => _buildRssSections(detail),
          ContentReaderKind.novel => _buildNovelSections(detail),
          ContentReaderKind.comic => _buildComicSections(detail),
          ContentReaderKind.subtitle => _buildSubtitleSections(detail),
          ContentReaderKind.unknown => const <Widget>[],
        },
      ],
    );
  }

  List<Widget> _buildArticleSections(ContentDetail detail) {
    final paragraphs =
        (detail.sections['paragraphs'] as List<dynamic>? ?? const [])
            .cast<String>();
    final highlights =
        (detail.sections['highlights'] as List<dynamic>? ?? const [])
            .cast<String>();

    return [
      for (final paragraph in paragraphs) ...[
        Text(paragraph),
        const SizedBox(height: 14),
      ],
      if (highlights.isNotEmpty)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('要点'),
                const SizedBox(height: 8),
                for (final item in highlights) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Icon(Icons.check_circle_outline, size: 16),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(item)),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ),
      const SizedBox(height: 8),
    ];
  }

  List<Widget> _buildRssSections(ContentDetail detail) {
    final feedItems =
        (detail.sections['feedItems'] as List<dynamic>? ?? const [])
            .cast<Map<String, String>>();
    return [
      for (final item in feedItems) ...[
        Card(
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            title: Text(item['title'] ?? ''),
            subtitle: Text(
              '${item['summary'] ?? ''}\n发布时间: ${item['publishedAt'] ?? '--'}',
            ),
            isThreeLine: true,
            leading: const Icon(Icons.feed_outlined),
          ),
        ),
        const SizedBox(height: 12),
      ],
    ];
  }

  List<Widget> _buildNovelSections(ContentDetail detail) {
    final chapters = (detail.sections['chapters'] as List<dynamic>? ?? const [])
        .cast<Map<String, Object?>>();
    return [
      for (final chapter in chapters) ...[
        Card(
          child: ExpansionTile(
            initiallyExpanded: chapter == chapters.first,
            title: Text('${chapter['title'] ?? ''}'),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              for (final paragraph
                  in (chapter['paragraphs'] as List<dynamic>? ?? const [])
                      .cast<String>()) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(paragraph),
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
    ];
  }

  List<Widget> _buildComicSections(ContentDetail detail) {
    final episodes = (detail.sections['episodes'] as List<dynamic>? ?? const [])
        .cast<Map<String, Object?>>();
    return [
      for (final episode in episodes) ...[
        Card(
          child: ExpansionTile(
            initiallyExpanded: episode == episodes.first,
            title: Text('${episode['title'] ?? ''}'),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              for (final panel
                  in (episode['panels'] as List<dynamic>? ?? const [])
                      .cast<String>()) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(Icons.crop_7_5_outlined, size: 18),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(panel)),
                  ],
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
    ];
  }

  List<Widget> _buildSubtitleSections(ContentDetail detail) {
    final cues = (detail.sections['cues'] as List<dynamic>? ?? const [])
        .cast<Map<String, String>>();
    return [
      for (final cue in cues) ...[
        Card(
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            title: Text(cue['text'] ?? ''),
            subtitle: Text(
              '${cue['start'] ?? '--'} - ${cue['end'] ?? '--'}\n${cue['note'] ?? ''}',
            ),
            isThreeLine: true,
            leading: const Icon(Icons.subtitles_outlined),
          ),
        ),
        const SizedBox(height: 12),
      ],
    ];
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

IconData _readerIcon(ContentEntity entity) {
  switch (entity.readerKind) {
    case ContentReaderKind.rss:
      return Icons.rss_feed_outlined;
    case ContentReaderKind.novel:
      return Icons.menu_book_outlined;
    case ContentReaderKind.comic:
      return Icons.collections_bookmark_outlined;
    case ContentReaderKind.subtitle:
      return Icons.subtitles_outlined;
    case ContentReaderKind.webArticle:
      return Icons.article_outlined;
    case ContentReaderKind.unknown:
      return Icons.description_outlined;
  }
}

String _readerKindLabel(ContentEntity entity) {
  switch (entity.readerKind) {
    case ContentReaderKind.rss:
      return 'RSS';
    case ContentReaderKind.novel:
      return '小说';
    case ContentReaderKind.comic:
      return '漫画';
    case ContentReaderKind.subtitle:
      return '字幕';
    case ContentReaderKind.webArticle:
      return '网页文章';
    case ContentReaderKind.unknown:
      return '内容';
  }
}

String? _metadataLabel(ContentEntity entity) {
  switch (entity.readerKind) {
    case ContentReaderKind.webArticle:
      return '${entity.metadata['readingTime'] ?? ''}';
    case ContentReaderKind.rss:
      return '${entity.metadata['frequency'] ?? ''}';
    case ContentReaderKind.novel:
      return '共 ${entity.metadata['chapterCount'] ?? '--'} 章';
    case ContentReaderKind.comic:
      return '共 ${entity.metadata['episodeCount'] ?? '--'} 话';
    case ContentReaderKind.subtitle:
      return '${entity.metadata['languagePair'] ?? ''}';
    case ContentReaderKind.unknown:
      return null;
  }
}

String _saveModeLabel(ContentSaveMode mode) {
  switch (mode) {
    case ContentSaveMode.favorite:
      return '收藏';
    case ContentSaveMode.bookmark:
      return '书签';
    case ContentSaveMode.archive:
      return '归档';
    case ContentSaveMode.history:
      return '历史';
  }
}

String _subscriptionStateLabel(ContentSubscriptionState state) {
  switch (state) {
    case ContentSubscriptionState.active:
      return '活跃';
    case ContentSubscriptionState.paused:
      return '暂停';
    case ContentSubscriptionState.cancelled:
      return '已取消';
  }
}
