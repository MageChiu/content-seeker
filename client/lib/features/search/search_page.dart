// 搜索主页面
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/search_result.dart';
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

  void _onSearch() {
    final query = _controller.text.trim();
    if (query.isEmpty) return;
    final settings = context.read<SettingsProvider>();
    // #region debug-point A:search-submit
    _debugReportSearchPage('submit search', {
      'query': query,
      'strategy': settings.searchStrategy.name,
      'mediaTypeFilter': _mediaTypeFilter?.name,
      'enabledLocalSources': settings.enabledLocalSources,
      'localReady': {
        'youtube': settings.isLocalSourceReady('youtube'),
        'bilibili': settings.isLocalSourceReady('bilibili'),
      },
    });
    // #endregion
    _focusNode.unfocus();
    context
        .read<SearchProvider>()
        .search(query, mediaTypeFilter: _mediaTypeFilter);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Content Seeker'),
        actions: [
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
                          hintText: '用自然语言搜索视频或音频...',
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
                        selected: _mediaTypeFilter == null,
                        onSelected: (_) {
                          setState(() {
                            _mediaTypeFilter = null;
                          });
                          context
                              .read<SearchProvider>()
                              .setMediaTypeFilter(null);
                        },
                      ),
                      ChoiceChip(
                        label: const Text('视频'),
                        selected: _mediaTypeFilter == MediaType.video,
                        onSelected: (selected) {
                          setState(() {
                            _mediaTypeFilter =
                                selected ? MediaType.video : null;
                          });
                          context.read<SearchProvider>().setMediaTypeFilter(
                                selected ? MediaType.video : null,
                              );
                        },
                      ),
                      ChoiceChip(
                        label: const Text('音频'),
                        selected: _mediaTypeFilter == MediaType.audio,
                        onSelected: (selected) {
                          setState(() {
                            _mediaTypeFilter =
                                selected ? MediaType.audio : null;
                          });
                          context.read<SearchProvider>().setMediaTypeFilter(
                                selected ? MediaType.audio : null,
                              );
                        },
                      ),
                    ],
                  ),
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
                  return const Center(child: Text('没有找到相关内容'));
                }
                if (provider.results.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.play_circle_outline,
                            size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          '输入关键词搜索视频或音频',
                          style: TextStyle(color: Colors.grey, fontSize: 16),
                        ),
                        SizedBox(height: 8),
                        Text(
                          '支持自然语言，如 "讲解 K8s 调度的视频"',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: provider.results.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return _SearchOptimizationHint(provider: provider);
                    }
                    return _ResultCard(result: provider.results[index - 1]);
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
    final canOpenExternally = result.hasPlayUrl;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PlayerPage(result: result),
          ),
        ),
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
                            result.mediaType == MediaType.audio
                                ? Icons.music_note
                                : Icons.video_library,
                          ),
                        ),
                  // 时长标签
                  if (result.durationSeconds > 0)
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
                        if (result.durationSeconds > 0) ...[
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
                                : result.hasHighlights
                                    ? Icons.subtitles
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
                    Row(
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => PlayerPage(result: result),
                            ),
                          ),
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('站内播放'),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: '浏览器打开',
                          onPressed: canOpenExternally
                              ? () => _openUrl(result.playUrl)
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
      case 'podcast':
        return Colors.teal;
      case 'google':
        return Colors.indigo;
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
