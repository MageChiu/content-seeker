// 设置页面：搜索策略 + 本地搜索源配置 + LLM 配置
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import '../../core/source_catalog.dart';
import '../../platform/directory_access.dart';
import 'settings_provider.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('设置'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: '搜索源'),
              Tab(text: 'RSS 阅读源'),
              Tab(text: '播放偏好'),
              Tab(text: '存储目录'),
              Tab(text: '本地 LLM'),
            ],
          ),
        ),
        body: Consumer<SettingsProvider>(
          builder: (context, settings, _) {
            return TabBarView(
              children: [
                _buildSearchTab(context, settings),
                _buildRssTab(context, settings),
                _buildPlaybackTab(context, settings),
                _buildStorageTab(context, settings),
                _buildLlmTab(context, settings),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSearchTab(BuildContext context, SettingsProvider settings) {
    final videoSources = settings.availableSources
        .where((d) => d.supportsVideo)
        .toList();
    final audioSources = settings.availableSources
        .where((d) => d.supportsAudio)
        .toList();
    final otherSources = settings.availableSources
        .where((d) => !d.supportsVideo && !d.supportsAudio)
        .toList();

    final mediaTabs = <Tab>[
      Tab(text: '视频源 (${videoSources.length})'),
      Tab(text: '音频源 (${audioSources.length})'),
      if (otherSources.isNotEmpty) Tab(text: '其它源 (${otherSources.length})'),
    ];
    final mediaViews = <Widget>[
      _buildSourceList(context, settings, videoSources),
      _buildSourceList(context, settings, audioSources),
      if (otherSources.isNotEmpty)
        _buildSourceList(context, settings, otherSources),
    ];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionHeader(title: '搜索策略'),
              DropdownButtonFormField<SearchStrategy>(
                initialValue: settings.searchStrategy,
                decoration: const InputDecoration(
                  labelText: '搜索执行策略',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: SearchStrategy.preferRemote,
                    child: Text('优先远程'),
                  ),
                  DropdownMenuItem(
                    value: SearchStrategy.preferLocal,
                    child: Text('优先本地'),
                  ),
                  DropdownMenuItem(
                    value: SearchStrategy.localOnly,
                    child: Text('只有本地'),
                  ),
                  DropdownMenuItem(
                    value: SearchStrategy.remoteOnly,
                    child: Text('只有远程'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    settings.setSearchStrategy(value);
                  }
                },
              ),
              const SizedBox(height: 12),
              const _SectionHeader(title: '内容源'),
              Text(
                '内容源按媒体类型分组，只展示 client 内真正可用的本地搜索源。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        Expanded(
          child: DefaultTabController(
            length: mediaTabs.length,
            child: Column(
              children: [
                TabBar(
                  isScrollable: true,
                  tabs: mediaTabs,
                ),
                Expanded(
                  child: TabBarView(children: mediaViews),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSourceList(
    BuildContext context,
    SettingsProvider settings,
    List<ContentSourceDescriptor> sources,
  ) {
    if (sources.isEmpty) {
      return Center(
        child: Text(
          '该分组暂无可用的本地搜索源',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final descriptor in sources) ...[
          _SourceTile(
            descriptor: descriptor,
            config: settings.sourceConfigs[descriptor.key]!,
            isLocalReady: settings.isLocalSourceReady(descriptor.key),
            capabilitySummary:
                settings.sourceSearchCapabilitySummary(descriptor.key),
            onEnabledChanged: (value) =>
                settings.setSourceEnabled(descriptor.key, value),
            onCredentialChanged: descriptor.requiresLocalApiKey
                ? (value) => settings.setSourceApiKey(descriptor.key, value)
                : null,
            onCredentialFieldChanged: (credKey, value) =>
                settings.setSourceCredential(descriptor.key, credKey, value),
            onCustomBaseUrlChanged: descriptor.supportsCustomBaseUrl
                ? (value) =>
                    settings.setSourceCustomBaseUrl(descriptor.key, value)
                : null,
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _buildRssTab(BuildContext context, SettingsProvider settings) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _SectionHeader(title: 'RSS 阅读源'),
        Text(
          '这里维护可订阅、可搜索的 RSS 列表，后续新增阅读源只需要继续添加即可。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        _RssFeedSection(settings: settings),
      ],
    );
  }

  Widget _buildPlaybackTab(BuildContext context, SettingsProvider settings) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _SectionHeader(title: '播放偏好'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '默认倍速 ${_formatPlaybackRate(settings.playbackRate)}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Slider(
                  value: settings.playbackRate,
                  min: 0.5,
                  max: 2.0,
                  divisions: 6,
                  label: _formatPlaybackRate(settings.playbackRate),
                  onChanged: settings.setPlaybackRate,
                ),
                const SizedBox(height: 8),
                Text(
                  '默认音量 ${settings.playbackVolume.round()}%',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Slider(
                  value: settings.playbackVolume,
                  min: 0,
                  max: 100,
                  divisions: 20,
                  label: '${settings.playbackVolume.round()}%',
                  onChanged: settings.setPlaybackVolume,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: settings.playbackSeekSeconds,
                  decoration: const InputDecoration(
                    labelText: '快进 / 快退步长',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 5, child: Text('5 秒')),
                    DropdownMenuItem(value: 10, child: Text('10 秒')),
                    DropdownMenuItem(value: 15, child: Text('15 秒')),
                    DropdownMenuItem(value: 30, child: Text('30 秒')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      settings.setPlaybackSeekSeconds(value);
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStorageTab(BuildContext context, SettingsProvider settings) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _SectionHeader(title: 'Runtime 存储策略'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('启用 Runtime 渐进缓存'),
                  subtitle: const Text(
                    '让 runtime 在播放网络流时复用本地缓存，减少重复下载并提升弱网场景稳定性',
                  ),
                  value: settings.playbackCacheEnabled,
                  onChanged: settings.setRuntimeProgressiveCacheEnabled,
                ),
                const SizedBox(height: 8),
                Text(
                  '缓存目录',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  settings.playbackCacheDir.isEmpty
                      ? '默认：应用支持目录下的 content_seeker_cache/（沙箱内可写）'
                      : settings.playbackCacheDir,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (_isMacOSLegacyPath(
                  settings.playbackCacheDir,
                  settings.playbackCacheDirBookmark,
                )) ...[
                  const SizedBox(height: 6),
                  Text(
                    '当前是旧配置/手动输入路径，未保存 macOS 授权信息。'
                    '播放时会自动回退到应用内缓存目录，请重新用“浏览选择目录”选择一次。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                  ),
                ],
                if (settings.playbackCacheDir.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _MacOSDirectoryStatus(
                    path: settings.playbackCacheDir,
                    bookmark: settings.playbackCacheDirBookmark,
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('自定义 Runtime 缓存目录'),
                      onPressed: () => _showCacheDirDialog(context, settings),
                    ),
                    if (settings.playbackCacheDir.isNotEmpty)
                      TextButton(
                        onPressed: () =>
                            settings.setRuntimeCacheDirSelection(''),
                        child: const Text('恢复默认'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'macOS 沙箱模式下，强烈建议使用「浏览选择目录」让系统授予持久写入权限，'
                  '否则手动输入的 ~/Downloads/ 等路径可能无写入权限。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).hintColor,
                      ),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 32),
        const _SectionHeader(title: 'Runtime 录制目录'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '录制保存目录',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  settings.recordingDir.isEmpty
                      ? '默认：应用文档目录下的 content_seeker_recordings/'
                      : settings.recordingDir,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (_isMacOSLegacyPath(
                  settings.recordingDir,
                  settings.recordingDirBookmark,
                )) ...[
                  const SizedBox(height: 6),
                  Text(
                    '当前是旧配置/手动输入路径，未保存 macOS 授权信息。'
                    '录制时会自动回退到应用内目录，请重新用“浏览选择目录”选择一次。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                  ),
                ],
                if (settings.recordingDir.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _MacOSDirectoryStatus(
                    path: settings.recordingDir,
                    bookmark: settings.recordingDirBookmark,
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('自定义 Runtime 录制目录'),
                      onPressed: () =>
                          _showRecordingDirDialog(context, settings),
                    ),
                    if (settings.recordingDir.isNotEmpty)
                      TextButton(
                        onPressed: () =>
                            settings.setRuntimeRecordingDirSelection(''),
                        child: const Text('恢复默认'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '这里定义的是 runtime 在需要落盘录制数据时使用的目标目录。'
                  '推荐通过「浏览选择目录」选择 ~/Movies/ 内的子目录，沙箱会自动授权写入。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).hintColor,
                      ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLlmTab(BuildContext context, SettingsProvider settings) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _SectionHeader(title: '本地 LLM 配置'),
        SwitchListTile(
          title: const Text('启用本地 LLM Key'),
          subtitle: const Text('该配置仅为本地搜索增强预留，不影响本地源配置'),
          value: settings.useLocalLlm,
          onChanged: settings.setUseLocalLlm,
        ),
        if (settings.useLocalLlm) ...[
          DropdownButtonFormField<LlmProviderType>(
            initialValue: settings.llmProvider,
            decoration: const InputDecoration(
              labelText: 'LLM 提供商',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(
                value: LlmProviderType.openai,
                child: Text('OpenAI'),
              ),
              DropdownMenuItem(
                value: LlmProviderType.deepseek,
                child: Text('DeepSeek'),
              ),
              DropdownMenuItem(
                value: LlmProviderType.ollama,
                child: Text('Ollama'),
              ),
              DropdownMenuItem(
                value: LlmProviderType.custom,
                child: Text('自定义兼容接口'),
              ),
            ],
            onChanged: (value) {
              if (value != null) {
                settings.setLlmProvider(value);
              }
            },
          ),
          const SizedBox(height: 12),
          _TextFieldTile(
            label: 'Base URL',
            hint: _llmBaseUrlHint(settings.llmProvider),
            initialValue: settings.llmBaseUrl,
            onChanged: settings.setLlmBaseUrl,
          ),
          const SizedBox(height: 12),
          _TextFieldTile(
            label: '模型名',
            hint: _llmModelHint(settings.llmProvider),
            initialValue: settings.llmModel,
            onChanged: settings.setLlmModel,
          ),
          const SizedBox(height: 12),
          _TextFieldTile(
            label: _llmApiKeyLabel(settings.llmProvider),
            hint: _llmApiKeyHint(settings.llmProvider),
            initialValue: settings.llmApiKey,
            onChanged: settings.setLlmApiKey,
            obscure: settings.llmProvider != LlmProviderType.ollama,
          ),
        ],
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  final ContentSourceDescriptor descriptor;
  final SourceConfig config;
  final bool isLocalReady;
  final String capabilitySummary;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<String>? onCredentialChanged;
  final void Function(String credKey, String value)? onCredentialFieldChanged;
  final ValueChanged<String>? onCustomBaseUrlChanged;

  const _SourceTile({
    required this.descriptor,
    required this.config,
    required this.isLocalReady,
    required this.capabilitySummary,
    required this.onEnabledChanged,
    required this.onCredentialChanged,
    this.onCredentialFieldChanged,
    this.onCustomBaseUrlChanged,
  });

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      descriptor.localSearchDescription,
      capabilitySummary,
      '状态: ${config.enabled ? '已启用' : '已关闭'}',
    ].join('\n');

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
        child: Column(
          children: [
            SwitchListTile(
              title: Text(descriptor.label),
              subtitle: Text(subtitle),
              value: config.enabled,
              onChanged: onEnabledChanged,
              secondary: Icon(
                _sourceIcon(descriptor.key),
                color: !config.enabled
                    ? Colors.grey
                    : descriptor.supportsLocalSearch && !isLocalReady
                        ? Colors.orange
                        : Colors.green,
              ),
            ),
            if (config.enabled && descriptor.credentialHints.isNotEmpty)
              for (final hint in descriptor.credentialHints)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: _TextFieldTile(
                    label: hint.label,
                    hint: hint.hint,
                    initialValue: config.credentials[hint.credKey] ?? '',
                    onChanged: (value) {
                      onCredentialFieldChanged?.call(hint.credKey, value);
                      // 兼容旧逻辑
                      if (hint.credKey == 'apiKey') {
                        onCredentialChanged?.call(value);
                      }
                    },
                    obscure: hint.obscure,
                    dense: true,
                  ),
                )
            else if (descriptor.requiresLocalApiKey && config.enabled)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: _TextFieldTile(
                  label: _credentialLabel(descriptor),
                  hint: _credentialHint(descriptor),
                  initialValue: config.apiKey,
                  onChanged: onCredentialChanged ?? (_) {},
                  obscure: true,
                  dense: true,
                ),
              ),
            if (descriptor.supportsCustomBaseUrl && config.enabled)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: _TextFieldTile(
                  label: '实例地址',
                  hint: '留空使用默认公共实例',
                  initialValue: config.customBaseUrl,
                  onChanged: onCustomBaseUrlChanged ?? (_) {},
                  obscure: false,
                  dense: true,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RssFeedSection extends StatelessWidget {
  final SettingsProvider settings;

  const _RssFeedSection({required this.settings});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '已配置 RSS 源',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => _showRssFeedDialog(context, settings),
                  icon: const Icon(Icons.add),
                  label: const Text('添加'),
                ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () => _importRssFeeds(context, settings),
                        icon: const Icon(Icons.file_upload_outlined),
                        label: const Text('导入'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () => _exportRssFeeds(context, settings),
                        icon: const Icon(Icons.file_download_outlined),
                        label: const Text('导出'),
                      ),
              ],
            ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: () {
                          final added = settings.addDefaultRssFeeds();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('已补充 $added 个常用 RSS 源')),
                          );
                        },
                        icon: const Icon(Icons.auto_awesome_outlined),
                        label: const Text('补充常用源'),
                      ),
                    ],
                  ),
            const SizedBox(height: 12),
            if (settings.rssFeeds.isEmpty)
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.rss_feed_outlined),
                title: Text('还没有 RSS 源'),
                subtitle: Text('添加后会进入阅读发现页，并参与统一搜索。'),
              ),
            for (final feed in settings.rssFeeds) ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(feed.title),
                subtitle: Text(
                  '${feed.subtitle.isEmpty ? '未填写说明' : feed.subtitle}\n${feed.url}',
                ),
                isThreeLine: true,
                value: feed.enabled,
                onChanged: (value) => settings.setRssFeedEnabled(feed.id, value),
                secondary: const Icon(Icons.rss_feed_outlined),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: () =>
                          _showRssFeedDialog(context, settings, initial: feed),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('编辑'),
                    ),
                    TextButton.icon(
                      onPressed: () => settings.removeRssFeed(feed.id),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('删除'),
                    ),
                  ],
                ),
              ),
              if (feed != settings.rssFeeds.last) const Divider(),
            ],
          ],
        ),
      ),
    );
  }
}

IconData _sourceIcon(String source) {
  switch (source) {
    case 'youtube':
      return Icons.ondemand_video;
    case 'bilibili':
      return Icons.live_tv;
    case 'itunes':
      return Icons.library_music;
    case 'jamendo':
      return Icons.audio_file;
    case 'dailymotion':
      return Icons.video_library;
    case 'vimeo':
      return Icons.play_circle_outline;
    case 'peertube':
      return Icons.connected_tv;
    case 'acfun':
      return Icons.smart_display;
    case 'youku':
      return Icons.ondemand_video_outlined;
    case 'deezer':
      return Icons.headphones;
    case 'internet_archive':
      return Icons.album_outlined;
    case 'internet_archive_video':
      return Icons.movie_creation_outlined;
    default:
      return Icons.extension;
  }
}

String _credentialLabel(ContentSourceDescriptor descriptor) {
  if (descriptor.key == 'jamendo') {
    return '${descriptor.label} Client ID';
  }
  return '${descriptor.label} API Key';
}

String _credentialHint(ContentSourceDescriptor descriptor) {
  if (descriptor.key == 'jamendo') {
    return '输入 ${descriptor.label} 所需的 Client ID';
  }
  return '输入 ${descriptor.label} 所需的本地搜索 Key';
}

String _llmBaseUrlHint(LlmProviderType provider) {
  switch (provider) {
    case LlmProviderType.openai:
      return 'https://api.openai.com/v1';
    case LlmProviderType.deepseek:
      return 'https://api.deepseek.com/v1';
    case LlmProviderType.ollama:
      return 'http://127.0.0.1:11434/v1';
    case LlmProviderType.custom:
      return '填写兼容 OpenAI 的接口地址';
  }
}

String _llmModelHint(LlmProviderType provider) {
  switch (provider) {
    case LlmProviderType.openai:
      return '如 gpt-4o-mini';
    case LlmProviderType.deepseek:
      return '如 deepseek-chat';
    case LlmProviderType.ollama:
      return '如 qwen2.5:7b';
    case LlmProviderType.custom:
      return '填写你的模型名';
  }
}

String _llmApiKeyLabel(LlmProviderType provider) {
  switch (provider) {
    case LlmProviderType.openai:
      return 'OpenAI API Key';
    case LlmProviderType.deepseek:
      return 'DeepSeek API Key';
    case LlmProviderType.ollama:
      return '鉴权 Token（可选）';
    case LlmProviderType.custom:
      return '接口 Key / Token';
  }
}

String _llmApiKeyHint(LlmProviderType provider) {
  switch (provider) {
    case LlmProviderType.openai:
    case LlmProviderType.deepseek:
      return 'sk-...';
    case LlmProviderType.ollama:
      return '如果你的本地网关需要鉴权可填写';
    case LlmProviderType.custom:
      return '填写接口需要的 Key 或 Token';
  }
}

String _formatPlaybackRate(double value) {
  return '${value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')}x';
}

class _TextFieldTile extends StatefulWidget {
  final String label;
  final String hint;
  final String initialValue;
  final ValueChanged<String> onChanged;
  final bool obscure;
  final bool dense;

  const _TextFieldTile({
    required this.label,
    required this.hint,
    required this.initialValue,
    required this.onChanged,
    this.obscure = false,
    this.dense = false,
  });

  @override
  State<_TextFieldTile> createState() => _TextFieldTileState();
}

class _TextFieldTileState extends State<_TextFieldTile> {
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialValue);
  }

  @override
  void didUpdateWidget(covariant _TextFieldTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue &&
        _ctrl.text != widget.initialValue) {
      _ctrl.text = widget.initialValue;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextField(
        controller: _ctrl,
        obscureText: widget.obscure,
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hint,
          border: const OutlineInputBorder(),
          isDense: widget.dense,
        ),
        onChanged: widget.onChanged,
      ),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }
}

Future<void> _showRssFeedDialog(
  BuildContext context,
  SettingsProvider settings, {
  RssFeedConfig? initial,
}) async {
  final titleCtrl = TextEditingController(text: initial?.title ?? '');
  final urlCtrl = TextEditingController(text: initial?.url ?? '');
  final subtitleCtrl = TextEditingController(text: initial?.subtitle ?? '');

  await showDialog<void>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(initial == null ? '添加 RSS 源' : '编辑 RSS 源'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(
                  labelText: '标题',
                  hintText: '例如：Hacker News Frontpage',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: urlCtrl,
                decoration: const InputDecoration(
                  labelText: 'RSS URL',
                  hintText: 'https://example.com/feed.xml',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: subtitleCtrl,
                decoration: const InputDecoration(
                  labelText: '说明',
                  hintText: '一句话描述这个阅读源',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              settings.upsertRssFeed(
                RssFeedConfig(
                  id: initial?.id ?? '',
                  title: titleCtrl.text,
                  url: urlCtrl.text,
                  subtitle: subtitleCtrl.text,
                  enabled: initial?.enabled ?? true,
                ),
              );
              Navigator.of(context).pop();
            },
            child: const Text('保存'),
          ),
        ],
      );
    },
  );

  titleCtrl.dispose();
  urlCtrl.dispose();
  subtitleCtrl.dispose();
}

Future<void> _importRssFeeds(
  BuildContext context,
  SettingsProvider settings,
) async {
  final file = await openFile(
    acceptedTypeGroups: const [
      XTypeGroup(
        label: 'JSON',
        extensions: ['json'],
      ),
    ],
  );
  if (file == null) {
    return;
  }
  try {
    final raw = await File(file.path).readAsString();
    final count = settings.importRssFeedsJson(raw);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已导入 $count 个 RSS 源')),
      );
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入失败: $error')),
      );
    }
  }
}

Future<void> _exportRssFeeds(
  BuildContext context,
  SettingsProvider settings,
) async {
  final location = await getSaveLocation(
    suggestedName: 'content_seeker_rss_feeds.json',
    acceptedTypeGroups: const [
      XTypeGroup(
        label: 'JSON',
        extensions: ['json'],
      ),
    ],
  );
  if (location == null) {
    return;
  }
  try {
    final file = File(location.path);
    final payload = settings.exportRssFeedsJson();
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(jsonDecode(payload)));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已导出到 ${file.path}')),
      );
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出失败: $error')),
      );
    }
  }
}

Future<void> _showRecordingDirDialog(
  BuildContext context,
  SettingsProvider settings,
) async {
  final picked = await _pickDirectory(
    context,
    title: '自定义录制目录',
    initial: settings.recordingDir,
    hint: '/Users/you/Movies/content_seeker_recordings',
  );
  if (picked != null && context.mounted) {
    if (picked.path.isEmpty) {
        settings.setRuntimeRecordingDirSelection('', bookmark: '');
      return;
    }
    final ok = await _verifyAndApplyDir(
      context,
      picked.path,
      bookmark: picked.bookmark,
    );
    if (ok) {
        settings.setRuntimeRecordingDirSelection(
        picked.path,
        bookmark: picked.bookmark,
      );
    }
  }
}

Future<void> _showCacheDirDialog(
  BuildContext context,
  SettingsProvider settings,
) async {
  final picked = await _pickDirectory(
    context,
    title: '自定义缓存目录',
    initial: settings.playbackCacheDir,
    hint: '/Users/you/Library/Caches/content_seeker',
  );
  if (picked != null && context.mounted) {
    if (picked.path.isEmpty) {
        settings.setRuntimeCacheDirSelection('', bookmark: '');
      return;
    }
    final ok = await _verifyAndApplyDir(
      context,
      picked.path,
      bookmark: picked.bookmark,
    );
    if (ok) {
        settings.setRuntimeCacheDirSelection(
        picked.path,
        bookmark: picked.bookmark,
      );
    }
  }
}

/// 验证目录可写，失败时弹错误对话框并返回 false
Future<bool> _verifyAndApplyDir(
  BuildContext context,
  String path, {
  String bookmark = '',
}) async {
  String? error;
  try {
    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.macOS &&
        bookmark.trim().isNotEmpty) {
      final resolved = await DirectoryAccess.resolveBookmark(bookmark);
      if (resolved == null) {
        error = '系统没有返回有效的 macOS 目录授权信息';
      } else if (!resolved.hasAccess) {
        error = resolved.error.isEmpty ? '未获得目录访问权限' : resolved.error;
      } else if (!resolved.writable) {
        error = resolved.error.isEmpty ? '目录授权存在，但当前不可写' : resolved.error;
      }
    }
    if (error != null) {
      throw Exception(error);
    }
    final dir = Directory(path);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final probe = File(p.join(path, '.seeker_write_probe'));
    await probe.writeAsString('ok', flush: true);
    final size = await probe.length();
    await probe.delete();
    if (size == 0) {
      error = '写入的探测文件大小为 0，目录可能存在异常';
    }
  } catch (e) {
    error = e.toString();
  }
  if (error != null && context.mounted) {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('目录无法使用'),
        content: Text(
          '无法写入到该目录：\n$path\n\n'
          '错误：$error\n\n'
          'macOS 沙箱限制：手动输入的路径（如 ~/Downloads/）可能无写入权限，'
          '请改用「浏览选择目录」从系统对话框选择路径。'
          '如果你已经是通过按钮选择的，说明这次 bookmark 授权恢复/写入探测也失败了，'
          '当前不会保存这条目录配置。',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('我知道了'),
          ),
        ],
      ),
    );
    return false;
  }
  return true;
}

Future<_PickedDirectory?> _pickDirectory(
  BuildContext context, {
  required String title,
  required String initial,
  required String hint,
}) async {
  final controller = TextEditingController(text: initial);
  String selectedBookmark = '';
  String selectedPath = initial.trim();
  return showDialog<_PickedDirectory>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText: hint,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.folder_open),
                label: const Text('浏览选择目录…（推荐，可绕过沙箱权限）'),
                onPressed: () async {
                  if (!ctx.mounted) return;
                  if (!kIsWeb &&
                      defaultTargetPlatform == TargetPlatform.macOS) {
                    final picked = await DirectoryAccess.pickDirectory();
                    if (picked != null) {
                      controller.text = picked.path;
                      selectedPath = picked.path;
                      selectedBookmark = picked.bookmark;
                    }
                    return;
                  }
                  final path =
                      await getDirectoryPath(confirmButtonText: '选择此目录');
                  if (path != null) {
                    controller.text = path;
                    selectedPath = path;
                    selectedBookmark = '';
                  }
                },
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '留空表示使用默认目录。\n'
              'macOS 沙箱模式下，强烈建议通过「浏览选择目录」选择路径，'
              '系统会自动授予应用持久写权限。',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final path = controller.text.trim();
              Navigator.of(ctx).pop(
                _PickedDirectory(
                  path: path,
                  bookmark: path == selectedPath ? selectedBookmark : '',
                ),
              );
            },
            child: const Text('保存'),
          ),
        ],
      );
    },
  );
}

class _PickedDirectory {
  final String path;
  final String bookmark;

  const _PickedDirectory({
    required this.path,
    this.bookmark = '',
  });
}

class _MacOSDirectoryStatus extends StatelessWidget {
  final String path;
  final String bookmark;

  const _MacOSDirectoryStatus({
    required this.path,
    required this.bookmark,
  });

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) {
      return const SizedBox.shrink();
    }
    final trimmedPath = path.trim();
    if (trimmedPath.isEmpty) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final trimmedBookmark = bookmark.trim();
    if (trimmedBookmark.isEmpty) {
      return Text(
        '授权状态：未保存 macOS bookmark，仅记录了路径；实际写入时大概率会被沙箱拒绝。',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.error,
        ),
      );
    }

    return FutureBuilder<DirectoryAccessResult?>(
      future: DirectoryAccess.resolveBookmark(trimmedBookmark),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Text(
            '授权状态：正在校验 macOS 目录访问权限...',
            style: theme.textTheme.bodySmall,
          );
        }
        if (snapshot.hasError) {
          return Text(
            '授权状态：bookmark 恢复失败，当前目录可能无法写入。${snapshot.error}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          );
        }
        final data = snapshot.data;
        if (data == null) {
          return Text(
            '授权状态：系统未返回有效的目录授权信息。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          );
        }
        if (data.hasAccess && data.writable) {
          return Text(
            '授权状态：macOS bookmark 已恢复，当前目录写入探测通过。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.green.shade700,
            ),
          );
        }
        final message = data.error.isEmpty ? '目录当前不可写' : data.error;
        return Text(
          '授权状态：bookmark 已存在，但本次原生写入探测失败。$message',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.error,
          ),
        );
      },
    );
  }
}

bool _isMacOSLegacyPath(String path, String bookmark) {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) {
    return false;
  }
  return path.trim().isNotEmpty && bookmark.trim().isEmpty;
}
