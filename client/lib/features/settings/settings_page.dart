// 设置页面：搜索策略 + 本地搜索源配置 + LLM 配置
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/source_catalog.dart';
import 'settings_provider.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: Consumer<SettingsProvider>(
        builder: (context, settings, _) {
          return ListView(
            padding: const EdgeInsets.all(16),
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
              const SizedBox(height: 8),
              Text(
                _strategyDescription(settings.searchStrategy),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const Divider(height: 32),
              const _SectionHeader(title: '服务端配置'),
              _TextFieldTile(
                label: '服务端地址',
                hint: 'http://localhost:8000',
                initialValue: settings.serverUrl,
                onChanged: settings.setServerUrl,
              ),
              const SizedBox(height: 8),
              Text(
                '客户端本地搜索是基础能力；服务端搜索是可选增强。下面的内容源开关会同时影响本地与远程可用性。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const Divider(height: 32),
              const _SectionHeader(title: '内容源'),
              Text(
                '建议优先保证本地源可用，再按需开启远程增强；即使服务端不可用，本地搜索也应能独立工作。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              for (final descriptor in settings.availableSources) ...[
                _SourceTile(
                  descriptor: descriptor,
                  config: settings.sourceConfigs[descriptor.key]!,
                  isLocalReady: settings.isLocalSourceReady(descriptor.key),
                  capabilitySummary:
                      settings.sourceSearchCapabilitySummary(descriptor.key),
                  onEnabledChanged: (value) =>
                      settings.setSourceEnabled(descriptor.key, value),
                  onCredentialChanged: descriptor.requiresLocalApiKey
                      ? (value) =>
                          settings.setSourceApiKey(descriptor.key, value)
                      : null,
                ),
                const SizedBox(height: 8),
              ],
              const Divider(height: 32),
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
              const Divider(height: 32),
              const _SectionHeader(title: '本地 LLM 配置'),
              SwitchListTile(
                title: const Text('启用本地 LLM Key'),
                subtitle: const Text('该配置仅为本地搜索增强预留，不影响远程服务端配置'),
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
        },
      ),
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

String _strategyDescription(SearchStrategy strategy) {
  switch (strategy) {
    case SearchStrategy.preferRemote:
      return '先走远程服务；远程没有结果时再回退到本地。';
    case SearchStrategy.preferLocal:
      return '先走本地搜索；本地没有结果时再回退到远程。';
    case SearchStrategy.localOnly:
      return '只使用本地搜索源，不调用服务端。';
    case SearchStrategy.remoteOnly:
      return '只使用远程服务端，不调用本地搜索源。';
  }
}

class _SourceTile extends StatelessWidget {
  final ContentSourceDescriptor descriptor;
  final SourceConfig config;
  final bool isLocalReady;
  final String capabilitySummary;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<String>? onCredentialChanged;

  const _SourceTile({
    required this.descriptor,
    required this.config,
    required this.isLocalReady,
    required this.capabilitySummary,
    required this.onEnabledChanged,
    required this.onCredentialChanged,
  });

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      descriptor.localSearchDescription,
      descriptor.remoteSearchDescription,
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
            if (descriptor.requiresLocalApiKey && config.enabled)
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
