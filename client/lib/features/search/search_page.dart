// 搜索主页面
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app/download/download_coordinator.dart';
import '../../app/content/content_bridge.dart';
import '../../app/content/content_request.dart';
import '../../core/source_catalog.dart';
import '../../domain/download/download_status.dart';
import '../../models/search_result.dart';
import '../download/downloads_page.dart';
import '../reader/reader_page.dart';
import '../reader/reader_provider.dart';
import '../player/player_page.dart';
import 'search_provider.dart';
import '../settings/settings_page.dart';
import '../settings/settings_provider.dart';

// #region debug-point A:search-entry
void _debugReportSearchPage(String msg, Map<String, dynamic> data) {
  final client = HttpClient();
  unawaited(() async {
    try {
      final request =
          await client.postUrl(Uri.parse('http://127.0.0.1:7777/event'));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'sessionId': 'local-bilibili-search',
        'runId': 'pre-fix',
        'hypothesisId': 'A',
        'location': 'search_page.dart:_onSearch',
        'msg': '[DEBUG] $msg',
        'data': data,
        'ts': DateTime.now().millisecondsSinceEpoch,
      }));
      final response = await request.close();
      await response.drain<void>();
      client.close();
    } catch (_) {
      client.close(force: true);
    }
  }());
}
// #endregion

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  MediaType? _mediaTypeFilter;
  bool _readingOnly = false;

  void _applyFilter({
    required MediaType? mediaType,
    required bool readingOnly,
  }) {
    setState(() {
      _mediaTypeFilter = mediaType;
      _readingOnly = readingOnly;
    });
    context
        .read<SearchProvider>()
        .setSearchFilter(mediaType: mediaType, readingOnly: readingOnly);
    // 若已经搜索过，切换标签时直接用新筛选重新出结果
    if (_controller.text.trim().isNotEmpty) {
      _onSearch();
    }
  }

  void _onSearch() {
    final query = _controller.text.trim();
    if (query.isEmpty) return;
    final settings = context.read<SettingsProvider>();
    // #region debug-point A:search-submit
    _debugReportSearchPage('submit search', {
      'query': query,
      'strategy': settings.searchStrategy.name,
      'mediaTypeFilter': _mediaTypeFilter?.name,
        'readingOnly': _readingOnly,
      'enabledLocalSources': settings.enabledLocalSources,
      'localReady': {
        'youtube': settings.isLocalSourceReady('youtube'),
        'bilibili': settings.isLocalSourceReady('bilibili'),
        'dailymotion': settings.isLocalSourceReady('dailymotion'),
        'vimeo': settings.isLocalSourceReady('vimeo'),
        'peertube': settings.isLocalSourceReady('peertube'),
        'acfun': settings.isLocalSourceReady('acfun'),
        'youku': settings.isLocalSourceReady('youku'),
        'itunes': settings.isLocalSourceReady('itunes'),
        'jamendo': settings.isLocalSourceReady('jamendo'),
        'deezer': settings.isLocalSourceReady('deezer'),
        'internet_archive': settings.isLocalSourceReady('internet_archive'),
        'internet_archive_video':
            settings.isLocalSourceReady('internet_archive_video'),
      },
    });
    // #endregion
    _focusNode.unfocus();
    context
        .read<SearchProvider>()
        .search(
          query,
          mediaTypeFilter: _mediaTypeFilter,
          readingOnly: _readingOnly,
        );
  }

  void _showUrlPlayDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('URL 播放'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '输入远程地址 (http/https/rtmp/...)',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
          onSubmitted: (_) => _playUrl(ctx, controller.text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => _playUrl(ctx, controller.text),
            child: const Text('播放'),
          ),
        ],
      ),
    );
  }

  void _playUrl(BuildContext dialogContext, String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return;
    Navigator.pop(dialogContext);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerPage(
          request: ContentRequest(
            intent: ContentIntent.playback,
            contentId: '',
            sourceId: '',
            title: Uri.tryParse(trimmed)?.pathSegments.lastOrNull ?? trimmed,
            mediaType: _guessMediaType(trimmed),
            primaryUri: Uri.tryParse(trimmed),
            fallbackUri: Uri.tryParse(trimmed),
          ),
        ),
      ),
    );
  }

  ContentMediaType _guessMediaType(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('.mp3') ||
        lower.contains('.m4a') ||
        lower.contains('.aac') ||
        lower.contains('.wav') ||
        lower.contains('.flac') ||
        lower.contains('.ogg')) {
      return ContentMediaType.audio;
    }
    return ContentMediaType.video;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Content Seeker'),
        actions: [
          IconButton(
            icon: const Icon(Icons.menu_book_outlined),
            tooltip: '阅读内容',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ReaderPage()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: '下载与离线',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DownloadsPage()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.link),
            tooltip: 'URL 播放',
            onPressed: () => _showUrlPlayDialog(context),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsPage()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // 搜索栏
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        decoration: InputDecoration(
                          hintText: '搜索视频、音频或阅读内容...',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                        ),
                        onSubmitted: (_) => _onSearch(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: _onSearch,
                      icon: const Icon(Icons.search),
                      label: const Text('搜索'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('全部'),
                        selected: _mediaTypeFilter == null && !_readingOnly,
                        onSelected: (_) {
                          _applyFilter(mediaType: null, readingOnly: false);
                        },
                      ),
                      ChoiceChip(
                        label: const Text('视频'),
                        selected: _mediaTypeFilter == MediaType.video,
                        onSelected: (selected) {
                          _applyFilter(
                            mediaType: selected ? MediaType.video : null,
                            readingOnly: false,
                          );
                        },
                      ),
                      ChoiceChip(
                        label: const Text('音频'),
                        selected: _mediaTypeFilter == MediaType.audio,
                        onSelected: (selected) {
                          _applyFilter(
                            mediaType: selected ? MediaType.audio : null,
                            readingOnly: false,
                          );
                        },
                      ),
                      ChoiceChip(
                        label: const Text('阅读'),
                        selected: _readingOnly,
                        onSelected: (selected) {
                          _applyFilter(
                            mediaType: selected ? null : _mediaTypeFilter,
                            readingOnly: selected,
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _LocalSourceHint(
                  mediaTypeFilter: _mediaTypeFilter,
                  readingOnly: _readingOnly,
                ),
              ],
            ),
          ),
          // 结果列表
          Expanded(
            child: Consumer<SearchProvider>(
              builder: (context, provider, _) {
                if (provider.loading) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (provider.error != null) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, size: 48),
                        const SizedBox(height: 8),
                        Text(provider.error!),
                      ],
                    ),
                  );
                }
                if (provider.results.isEmpty && provider.lastQuery.isNotEmpty) {
                  return _NoSearchResultState(provider: provider);
                }
                if (provider.results.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.play_circle_outline,
                            size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        const Text(
                          '输入关键词搜索视频、音频或阅读内容',
                          style: TextStyle(color: Colors.grey, fontSize: 16),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '支持自然语言，如 "讲解 K8s 调度的视频" 或 "Flutter 架构文章"',
                          style: TextStyle(color: Colors.grey),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.tonalIcon(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ReaderPage(),
                            ),
                          ),
                          icon: const Icon(Icons.menu_book_outlined),
                          label: const Text('打开阅读内容'),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: provider.results.length + 2,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return _SearchOptimizationHint(provider: provider);
                    }
                    if (index == 1) {
                      return _SourceResultSummary(provider: provider);
                    }
                    return _ResultCard(result: provider.results[index - 2]);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }
}

class _NoSearchResultState extends StatelessWidget {
  final SearchProvider provider;

  const _NoSearchResultState({required this.provider});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final readySources = settings.readyLocalSources.where((source) {
      final descriptor = sourceDescriptor(source);
      if (provider.mediaTypeFilter == MediaType.audio) {
        return descriptor.supportsAudio;
      }
      if (provider.mediaTypeFilter == MediaType.video) {
        return descriptor.supportsVideo;
      }
      return true;
    }).map(settings.sourceDisplayName).toList(growable: false);

    final suggestions = switch (provider.mediaTypeFilter) {
      MediaType.audio => '尝试使用“歌手 - 歌名”或去掉 live/remix 等版本词',
      MediaType.video => '尝试缩短关键词，保留作品名或作者名',
      null => '尝试缩短关键词，或切换到更具体的搜索类型',
    };

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off_outlined, size: 56, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              '没有找到相关内容',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              suggestions,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 12),
            if (readySources.isEmpty)
              const Text(
                '当前没有已就绪的本地源，请先到设置页启用并完成配置。',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              )
            else
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  const Chip(label: Text('当前已参与搜索的来源')),
                  for (final source in readySources) Chip(label: Text(source)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _SourceResultSummary extends StatelessWidget {
  final SearchProvider provider;

  const _SourceResultSummary({required this.provider});

  @override
  Widget build(BuildContext context) {
    if (provider.lastSourceResultCounts.isEmpty) {
      return const SizedBox.shrink();
    }

    final chips = provider.lastSourceResultCounts.entries
        .map(
          (entry) => Chip(
            label: Text(
              '${sourceDescriptor(entry.key).label} ${entry.value}',
            ),
          ),
        )
        .toList(growable: false);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Chip(
              avatar: const Icon(Icons.tune, size: 18),
              label: Text(
                '本轮检索 ${provider.lastRawResultCount} 条，去重后 ${provider.lastDedupedCount} 条',
              ),
            ),
            ...chips,
          ],
        ),
      ),
    );
  }
}

class _LocalSourceHint extends StatelessWidget {
  final MediaType? mediaTypeFilter;
  final bool readingOnly;

  const _LocalSourceHint({
    required this.mediaTypeFilter,
    required this.readingOnly,
  });

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    if (readingOnly) {
      return const Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Chip(
              avatar: Icon(Icons.menu_book_outlined, size: 18),
              label: Text('当前阅读搜索会使用这些在线阅读源'),
            ),
            Chip(label: Text('DEV Community')),
            Chip(label: Text('可配置 RSS')),
            Chip(label: Text('Project Gutenberg')),
          ],
        ),
      );
    }

    final readySources = settings.readyLocalSources
        .where((source) {
          final descriptor = sourceDescriptor(source);
          if (mediaTypeFilter == MediaType.video) {
            return descriptor.supportsVideo;
          }
          if (mediaTypeFilter == MediaType.audio) {
            return descriptor.supportsAudio;
          }
          return true;
        })
        .map(settings.sourceDisplayName)
        .toList(growable: false);

    final title = switch (mediaTypeFilter) {
      MediaType.video => '当前视频搜索会使用这些本地源',
      MediaType.audio => '当前音频搜索会使用这些本地源',
      null => '当前搜索会使用这些本地源',
    };

    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          Chip(
            avatar: const Icon(Icons.storage_outlined, size: 18),
            label: Text(title),
          ),
          if (readySources.isEmpty)
            const Chip(label: Text('暂无可用源，请先去设置页配置'))
          else
            for (final label in readySources) Chip(label: Text(label)),
        ],
      ),
    );
  }
}

class _SearchOptimizationHint extends StatelessWidget {
  final SearchProvider provider;

  const _SearchOptimizationHint({required this.provider});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final optimized = provider.localLlmOptimized;
    final parts = <String>[
      if (provider.localLlmRewriteApplied) '查询改写',
      if (provider.localLlmRerankApplied) '结果重排',
      if (provider.localLlmSummaryCount > 0)
        '生成 ${provider.localLlmSummaryCount} 条摘要',
    ];
    final detail = optimized ? parts.join(' · ') : '未启用或本次未生效';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: optimized
              ? Colors.amber.withValues(alpha: 0.10)
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: optimized
                ? Colors.amber.withValues(alpha: 0.35)
                : theme.colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              optimized ? Icons.auto_awesome : Icons.info_outline,
              size: 18,
              color: optimized ? Colors.amber[800] : theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                optimized
                    ? '本次结果已由本地 LLM 优化：$detail'
                    : '本次结果未经过本地 LLM 优化：$detail',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final SearchResult result;

  const _ResultCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summaryText = result.summaryText;
    final metaLine = result.metaLine;
    final highlightTimestamp = result.primaryHighlightTimestampLabel;
    final canOpenExternally = result.hasPlayUrl || result.hasCanonicalUrl;
    final actionLabel = result.isReadingResult
        ? '开始阅读'
        : result.canPlayInApp
            ? '站内播放'
            : '打开详情';
    final actionIcon =
        result.isReadingResult ? Icons.menu_book_outlined : Icons.play_arrow;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openPrimary(context),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 缩略图
            SizedBox(
              width: 160,
              height: 100,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  result.thumbnailUrl.isNotEmpty
                      ? Image.network(
                          result.thumbnailUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: Colors.grey[300],
                            child: const Icon(Icons.image_not_supported),
                          ),
                        )
                      : Container(
                          color: Colors.grey[300],
                          child: Icon(
                            _thumbnailIcon(),
                          ),
                        ),
                  // 时长标签
                  if (result.durationSeconds > 0 && result.isMediaResult)
                    Positioned(
                      bottom: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          result.durationFormatted,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // 信息区域
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      result.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    // 来源标签
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _sourceColor(result.source).withValues(
                              alpha: 0.1,
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            result.sourceLabel,
                            style: TextStyle(
                              fontSize: 11,
                              color: _sourceColor(result.source),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            result.mediaSubtypeLabel,
                            style: theme.textTheme.labelSmall,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: result.isPlayable
                                ? Colors.green.withValues(alpha: 0.12)
                                : theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            result.availabilityLabel,
                            style: theme.textTheme.labelSmall,
                          ),
                        ),
                        if (result.durationSeconds > 0 && result.isMediaResult) ...[
                          const SizedBox(width: 8),
                          Text(
                            result.durationFormatted,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (metaLine != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        metaLine,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (summaryText != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            result.hasAiSummary
                                ? Icons.auto_awesome
                                : result.hasHighlights && result.isMediaResult
                                    ? Icons.subtitles
                                    : result.isReadingResult
                                        ? Icons.article_outlined
                                        : Icons.notes,
                            size: 14,
                            color: result.hasAiSummary
                                ? Colors.amber[700]
                                : theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              highlightTimestamp != null &&
                                      result.hasHighlights &&
                                      !result.hasAiSummary
                                  ? '$highlightTimestamp  $summaryText'
                                  : summaryText,
                              maxLines: result.hasAiSummary ? 2 : 3,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: result.hasAiSummary
                                    ? Colors.amber[800]
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: () => _openPrimary(context),
                          icon: Icon(actionIcon),
                          label: Text(actionLabel),
                        ),
                        if (result.isReadingResult && result.supportsSave) ...[
                          OutlinedButton.icon(
                            onPressed: () => _saveReadingContent(context),
                            icon: const Icon(Icons.bookmark_add_outlined),
                            label: const Text('离线保存'),
                          ),
                        ],
                        if ((result.isMediaResult && result.canDownloadDirectly) ||
                            (result.isReadingResult && result.canDownloadDirectly)) ...[
                          OutlinedButton.icon(
                            onPressed: () => _downloadMedia(context),
                            icon: const Icon(Icons.download_outlined),
                            label: const Text('下载'),
                          ),
                        ],
                        IconButton(
                          tooltip: result.isReadingResult ? '打开原文' : '浏览器打开',
                          onPressed: canOpenExternally
                              ? () => _openUrl(
                                    result.playUrl.isNotEmpty
                                        ? result.playUrl
                                        : result.canonicalUrl,
                                  )
                              : null,
                          icon: const Icon(Icons.open_in_browser),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _thumbnailIcon() {
    if (result.isReadingResult) {
      switch (result.contentTypeKey) {
        case 'webArticle':
          return Icons.article_outlined;
        case 'rss':
          return Icons.rss_feed_outlined;
        case 'novel':
          return Icons.auto_stories_outlined;
        case 'comic':
          return Icons.collections_bookmark_outlined;
        case 'subtitle':
          return Icons.subtitles_outlined;
      }
      return Icons.menu_book_outlined;
    }
    return result.mediaType == MediaType.audio
        ? Icons.music_note
        : Icons.video_library;
  }

  Future<void> _openPrimary(BuildContext context) async {
    if (result.canOpenInReader) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ReaderDetailPage(handle: result.toContentHandle()),
        ),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerPage(
          request: result.toContentRequest(),
        ),
      ),
    );
  }

  Future<void> _saveReadingContent(BuildContext context) async {
    try {
      final provider = context.read<ReaderProvider>();
      final detail = await provider.loadDetail(result.toContentHandle());
      await provider.saveDetail(detail);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已保存离线内容: ${result.title}')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $error')),
        );
      }
    }
  }

  Future<void> _downloadMedia(BuildContext context) async {
    try {
      final task = await context.read<DownloadCoordinator>().enqueue(
            result.toDownloadRequest(),
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

  Color _sourceColor(String source) {
    switch (source) {
      case 'youtube':
        return Colors.red;
      case 'bilibili':
        return Colors.blue;
      case 'spotify':
        return Colors.green;
      case 'itunes':
        return Colors.deepPurple;
      case 'jamendo':
        return Colors.orange;
      case 'deezer':
        return Colors.pink;
      case 'internet_archive':
        return Colors.brown;
      case 'audius':
        return Colors.purple;
      case 'podcast':
        return Colors.teal;
      case 'google':
        return Colors.indigo;
      case 'vimeo':
        return Colors.cyan;
      case 'peertube':
        return Colors.deepOrange;
      case 'acfun':
        return Colors.red;
      case 'youku':
        return Colors.blue;
      case 'dailymotion':
        return Colors.blueGrey;
      default:
        return Colors.grey;
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      if (kIsWeb) {
        await launchUrl(uri);
      } else {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }
}
