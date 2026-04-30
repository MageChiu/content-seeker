// 设置管理 Provider
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/source_catalog.dart';

enum SearchStrategy { preferRemote, preferLocal, localOnly, remoteOnly }

enum LlmProviderType { openai, deepseek, ollama, custom }

class SourceConfig {
  bool enabled;
  String apiKey;

  SourceConfig({
    this.enabled = true,
    this.apiKey = '',
  });

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'api_key': apiKey,
      };

  factory SourceConfig.fromJson(Map<String, dynamic> json) => SourceConfig(
        enabled: json['enabled'] ?? true,
        apiKey: json['api_key'] ?? '',
      );
}

class SettingsProvider extends ChangeNotifier {
  static const _storage = FlutterSecureStorage();
  static const _serverUrlKey = 'settings.server_url';
  static const _searchStrategyKey = 'settings.search_strategy';
  static const _sourceConfigsKey = 'settings.source_configs';
  static const _useLocalLlmKey = 'settings.use_local_llm';
  static const _llmProviderKey = 'settings.llm_provider';
  static const _llmApiKeyKey = 'settings.llm_api_key';
  static const _llmBaseUrlKey = 'settings.llm_base_url';
  static const _llmModelKey = 'settings.llm_model';
  static const _playbackRateKey = 'settings.playback_rate';
  static const _playbackVolumeKey = 'settings.playback_volume';
  static const _playbackSeekSecondsKey = 'settings.playback_seek_seconds';

  bool _initialized = false;
  bool get initialized => _initialized;

  String _serverUrl = 'http://localhost:8000';
  String get serverUrl => _serverUrl;

  SearchStrategy _searchStrategy = SearchStrategy.localOnly;
  SearchStrategy get searchStrategy => _searchStrategy;

  final Map<String, SourceConfig> _sourceConfigs =
      Map<String, SourceConfig>.fromEntries(
    kContentSourceCatalog.keys.map(
      (source) => MapEntry(source, SourceConfig(enabled: true)),
    ),
  );
  Map<String, SourceConfig> get sourceConfigs => _sourceConfigs;

  List<ContentSourceDescriptor> get availableSources =>
      kContentSourceCatalog.values.toList(
        growable: false,
      );

  bool _useLocalLlm = false;
  bool get useLocalLlm => _useLocalLlm;

  LlmProviderType _llmProvider = LlmProviderType.openai;
  LlmProviderType get llmProvider => _llmProvider;

  String _llmApiKey = '';
  String get llmApiKey => _llmApiKey;

  String _llmBaseUrl = _defaultLlmBaseUrl(LlmProviderType.openai);
  String get llmBaseUrl => _llmBaseUrl;

  String _llmModel = _defaultLlmModel(LlmProviderType.openai);
  String get llmModel => _llmModel;

  double _playbackRate = 1.0;
  double get playbackRate => _playbackRate;

  double _playbackVolume = 100.0;
  double get playbackVolume => _playbackVolume;

  int _playbackSeekSeconds = 10;
  int get playbackSeekSeconds => _playbackSeekSeconds;

  SettingsProvider() {
    _load();
  }

  List<String> get enabledSearchSources => _sourceConfigs.entries
      .where((entry) => entry.value.enabled)
      .map((entry) => entry.key)
      .toList(growable: false);

  List<String> get enabledLocalSources => enabledSearchSources
      .where(sourceSupportsLocalSearch)
      .toList(growable: false);

  List<String> get enabledRemoteSources => enabledSearchSources
      .where(sourceSupportsRemoteSearch)
      .toList(growable: false);

  List<String> get enabledRemoteSearchSources => enabledRemoteSources
      .where((source) => source != 'google')
      .toList(growable: false);

  List<String> get readyLocalSources =>
      enabledLocalSources.where(isLocalSourceReady).toList(growable: false);

  bool get canUseRemoteSearch => _serverUrl.trim().isNotEmpty;

  bool isRemoteSourceEnabled(String source) {
    return _sourceConfigs[source]?.enabled == true &&
        sourceSupportsRemoteSearch(source);
  }

  bool sourceRequiresApiKey(String source) {
    return sourceDescriptor(source).requiresLocalApiKey;
  }

  bool sourceSupportsLocalSearch(String source) {
    return sourceDescriptor(source).supportsLocalSearch;
  }

  bool sourceSupportsRemoteSearch(String source) {
    return sourceDescriptor(source).supportsRemoteSearch;
  }

  bool isLocalSourceReady(String source) {
    final config = _sourceConfigs[source];
    if (config == null || !config.enabled) {
      return false;
    }
    if (!sourceSupportsLocalSearch(source)) {
      return false;
    }
    if (!sourceRequiresApiKey(source)) {
      return true;
    }
    return config.apiKey.trim().isNotEmpty;
  }

  String sourceDisplayName(String source) {
    return sourceDescriptor(source).label;
  }

  String sourceSearchCapabilitySummary(String source) {
    final descriptor = sourceDescriptor(source);
    final remoteLabel = descriptor.supportsRemoteSearch ? '已启用' : '当前不支持';
    final localLabel = !descriptor.supportsLocalSearch
        ? '当前不支持'
        : isLocalSourceReady(source)
            ? '已就绪'
            : '待配置';
    return '远程搜索: $remoteLabel\n本地搜索: $localLabel';
  }

  void setServerUrl(String url) {
    _serverUrl = url;
    notifyListeners();
    unawaited(_writeSetting(_serverUrlKey, url));
  }

  void setSearchStrategy(SearchStrategy strategy) {
    _searchStrategy = strategy;
    notifyListeners();
    unawaited(_writeSetting(_searchStrategyKey, strategy.name));
  }

  void setSourceEnabled(String source, bool enabled) {
    final config = _sourceConfigs[source];
    if (config == null) {
      return;
    }
    config.enabled = enabled;
    notifyListeners();
    unawaited(_persistSourceConfigs());
  }

  void setSourceApiKey(String source, String key) {
    final config = _sourceConfigs[source];
    if (config == null) {
      return;
    }
    config.apiKey = key;
    notifyListeners();
    unawaited(_persistSourceConfigs());
  }

  void setUseLocalLlm(bool value) {
    _useLocalLlm = value;
    notifyListeners();
    unawaited(_writeSetting(_useLocalLlmKey, value.toString()));
  }

  void setLlmProvider(LlmProviderType provider) {
    final previousProvider = _llmProvider;
    _llmProvider = provider;
    if (_llmBaseUrl.trim().isEmpty ||
        _llmBaseUrl == _defaultLlmBaseUrl(previousProvider)) {
      _llmBaseUrl = _defaultLlmBaseUrl(provider);
    }
    if (_llmModel.trim().isEmpty ||
        _llmModel == _defaultLlmModel(previousProvider)) {
      _llmModel = _defaultLlmModel(provider);
    }
    notifyListeners();
    unawaited(_writeSetting(_llmProviderKey, provider.name));
    unawaited(_writeSetting(_llmBaseUrlKey, _llmBaseUrl));
    unawaited(_writeSetting(_llmModelKey, _llmModel));
  }

  void setLlmApiKey(String key) {
    _llmApiKey = key;
    notifyListeners();
    unawaited(_writeSetting(_llmApiKeyKey, key));
  }

  void setLlmBaseUrl(String value) {
    _llmBaseUrl = value;
    notifyListeners();
    unawaited(_writeSetting(_llmBaseUrlKey, value));
  }

  void setLlmModel(String value) {
    _llmModel = value;
    notifyListeners();
    unawaited(_writeSetting(_llmModelKey, value));
  }

  void setPlaybackRate(double value) {
    _playbackRate = value.clamp(0.5, 2.0);
    notifyListeners();
    unawaited(_writeSetting(_playbackRateKey, _playbackRate.toString()));
  }

  void setPlaybackVolume(double value) {
    _playbackVolume = value.clamp(0.0, 100.0);
    notifyListeners();
    unawaited(_writeSetting(_playbackVolumeKey, _playbackVolume.toString()));
  }

  void setPlaybackSeekSeconds(int value) {
    const allowedValues = {5, 10, 15, 30};
    _playbackSeekSeconds = allowedValues.contains(value) ? value : 10;
    notifyListeners();
    unawaited(
      _writeSetting(_playbackSeekSecondsKey, _playbackSeekSeconds.toString()),
    );
  }

  Future<void> _load() async {
    try {
      final values = await _storage.readAll();

      final savedServerUrl = values[_serverUrlKey];
      if (savedServerUrl != null && savedServerUrl.isNotEmpty) {
        _serverUrl = savedServerUrl;
      }

      final savedStrategy = values[_searchStrategyKey];
      if (savedStrategy != null) {
        _searchStrategy = SearchStrategy.values.firstWhere(
          (value) => value.name == savedStrategy,
          orElse: () => SearchStrategy.localOnly,
        );
      }

      final savedSources = values[_sourceConfigsKey];
      if (savedSources != null && savedSources.isNotEmpty) {
        final decoded = jsonDecode(savedSources) as Map<String, dynamic>;
        for (final entry in decoded.entries) {
          if (_sourceConfigs.containsKey(entry.key) &&
              entry.value is Map<String, dynamic>) {
            _sourceConfigs[entry.key] =
                SourceConfig.fromJson(entry.value as Map<String, dynamic>);
          }
        }
      }

      final savedUseLocalLlm = values[_useLocalLlmKey];
      if (savedUseLocalLlm != null) {
        _useLocalLlm = savedUseLocalLlm == 'true';
      }

      final savedLlmProvider = values[_llmProviderKey];
      if (savedLlmProvider != null) {
        _llmProvider = LlmProviderType.values.firstWhere(
          (value) => value.name == savedLlmProvider,
          orElse: () => LlmProviderType.openai,
        );
      }

      final savedLlmApiKey = values[_llmApiKeyKey];
      if (savedLlmApiKey != null) {
        _llmApiKey = savedLlmApiKey;
      }

      final savedLlmBaseUrl = values[_llmBaseUrlKey];
      if (savedLlmBaseUrl != null && savedLlmBaseUrl.isNotEmpty) {
        _llmBaseUrl = savedLlmBaseUrl;
      } else {
        _llmBaseUrl = _defaultLlmBaseUrl(_llmProvider);
      }

      final savedLlmModel = values[_llmModelKey];
      if (savedLlmModel != null && savedLlmModel.isNotEmpty) {
        _llmModel = savedLlmModel;
      } else {
        _llmModel = _defaultLlmModel(_llmProvider);
      }

      final savedPlaybackRate = double.tryParse(values[_playbackRateKey] ?? '');
      if (savedPlaybackRate != null) {
        _playbackRate = savedPlaybackRate.clamp(0.5, 2.0);
      }

      final savedPlaybackVolume = double.tryParse(
        values[_playbackVolumeKey] ?? '',
      );
      if (savedPlaybackVolume != null) {
        _playbackVolume = savedPlaybackVolume.clamp(0.0, 100.0);
      }

      final savedPlaybackSeekSeconds = int.tryParse(
        values[_playbackSeekSecondsKey] ?? '',
      );
      if (savedPlaybackSeekSeconds != null) {
        const allowedValues = {5, 10, 15, 30};
        _playbackSeekSeconds = allowedValues.contains(savedPlaybackSeekSeconds)
            ? savedPlaybackSeekSeconds
            : 10;
      }
    } catch (_) {
      // 配置加载失败时保留默认值，避免影响应用启动。
    } finally {
      _initialized = true;
      notifyListeners();
    }
  }

  Future<void> _persistSourceConfigs() async {
    final payload = jsonEncode(
      _sourceConfigs.map(
        (key, value) => MapEntry(key, value.toJson()),
      ),
    );
    await _writeSetting(_sourceConfigsKey, payload);
  }

  Future<void> _writeSetting(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (_) {
      // 本地调试环境缺少 macOS Keychain 能力时，允许以内存配置继续运行。
    }
  }

  static String _defaultLlmBaseUrl(LlmProviderType provider) {
    switch (provider) {
      case LlmProviderType.openai:
        return 'https://api.openai.com/v1';
      case LlmProviderType.deepseek:
        return 'https://api.deepseek.com/v1';
      case LlmProviderType.ollama:
        return 'http://127.0.0.1:11434/v1';
      case LlmProviderType.custom:
        return '';
    }
  }

  static String _defaultLlmModel(LlmProviderType provider) {
    switch (provider) {
      case LlmProviderType.openai:
        return 'gpt-4o-mini';
      case LlmProviderType.deepseek:
        return 'deepseek-chat';
      case LlmProviderType.ollama:
        return 'qwen2.5:7b';
      case LlmProviderType.custom:
        return '';
    }
  }
}
