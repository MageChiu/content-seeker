// 设置管理 Provider
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/source_catalog.dart';
import '../../domain/runtime/runtime_storage_policy.dart';

enum SearchStrategy { preferRemote, preferLocal, localOnly, remoteOnly }

enum LlmProviderType { openai, deepseek, ollama, custom }

class RssFeedConfig {
  final String id;
  final String title;
  final String url;
  final String subtitle;
  final bool enabled;

  const RssFeedConfig({
    required this.id,
    required this.title,
    required this.url,
    this.subtitle = '',
    this.enabled = true,
  });

  RssFeedConfig copyWith({
    String? id,
    String? title,
    String? url,
    String? subtitle,
    bool? enabled,
  }) {
    return RssFeedConfig(
      id: id ?? this.id,
      title: title ?? this.title,
      url: url ?? this.url,
      subtitle: subtitle ?? this.subtitle,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'url': url,
        'subtitle': subtitle,
        'enabled': enabled,
      };

  factory RssFeedConfig.fromJson(Map<String, dynamic> json) {
    return RssFeedConfig(
      id: '${json['id'] ?? ''}',
      title: '${json['title'] ?? ''}',
      url: '${json['url'] ?? ''}',
      subtitle: '${json['subtitle'] ?? ''}',
      enabled: json['enabled'] != false,
    );
  }
}

class SourceConfig {
  bool enabled;
  Map<String, String> credentials;
  String customBaseUrl;
  Map<String, String> extra;

  SourceConfig({
    this.enabled = true,
    Map<String, String>? credentials,
    this.customBaseUrl = '',
    Map<String, String>? extra,
  })  : credentials = credentials ?? {},
        extra = extra ?? {};

  /// 兼容旧版 apiKey 的快捷访问
  String get apiKey => credentials['apiKey'] ?? '';
  set apiKey(String value) => credentials['apiKey'] = value;

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'api_key': apiKey,
        'credentials': credentials,
        'custom_base_url': customBaseUrl,
        'extra': extra,
      };

  factory SourceConfig.fromJson(Map<String, dynamic> json) {
    final credentials = <String, String>{};
    // 兼容旧版 api_key 字段
    final legacyApiKey = json['api_key'] as String? ?? '';
    if (legacyApiKey.isNotEmpty) {
      credentials['apiKey'] = legacyApiKey;
    }
    // 新版 credentials 字段
    final rawCredentials = json['credentials'] as Map?;
    if (rawCredentials != null) {
      for (final entry in rawCredentials.entries) {
        credentials['${entry.key}'] = '${entry.value}';
      }
    }
    final rawExtra = json['extra'] as Map?;
    final extra = <String, String>{};
    if (rawExtra != null) {
      for (final entry in rawExtra.entries) {
        extra['${entry.key}'] = '${entry.value}';
      }
    }
    return SourceConfig(
      enabled: json['enabled'] ?? true,
      credentials: credentials,
      customBaseUrl: json['custom_base_url'] as String? ?? '',
      extra: extra,
    );
  }
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
  static const _recordingDirKey = 'settings.recording_dir';
  static const _recordingDirBookmarkKey = 'settings.recording_dir_bookmark';
  static const _playbackCacheEnabledKey = 'settings.playback_cache_enabled';
  static const _playbackCacheDirKey = 'settings.playback_cache_dir';
  static const _playbackCacheDirBookmarkKey =
      'settings.playback_cache_dir_bookmark';
  static const _rssFeedsKey = 'settings.rss_feeds';

  bool _initialized = false;
  bool get initialized => _initialized;

  String _serverUrl = 'http://localhost:8000';
  String get serverUrl => _serverUrl;

  SearchStrategy _searchStrategy = SearchStrategy.localOnly;
  SearchStrategy get searchStrategy => _searchStrategy;

  final Map<String, SourceConfig> _sourceConfigs =
      Map<String, SourceConfig>.fromEntries(
    kContentSourceCatalog.entries.map(
      (entry) => MapEntry(
        entry.key,
        SourceConfig(enabled: entry.value.enabledByDefault),
      ),
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

  /// 录制文件保存目录，空字符串表示使用应用文档目录默认子目录
  String _recordingDir = '';
  String get recordingDir => _recordingDir;
  String _recordingDirBookmark = '';
  String get recordingDirBookmark => _recordingDirBookmark;

  /// Runtime 渐进缓存开关：开启后 runtime 会把播放流复用到本地缓存目录，
  /// 用于加速重播并减少网络抖动场景下的重复下载
  bool _playbackCacheEnabled = false;
  bool get playbackCacheEnabled => _playbackCacheEnabled;

  /// 缓存目录，空字符串表示使用应用支持目录默认子目录
  String _playbackCacheDir = '';
  String get playbackCacheDir => _playbackCacheDir;
  String _playbackCacheDirBookmark = '';
  String get playbackCacheDirBookmark => _playbackCacheDirBookmark;

  RuntimeStoragePolicy get runtimeStoragePolicy => RuntimeStoragePolicy(
        progressiveCacheEnabled: _playbackCacheEnabled,
        cacheDirectory: RuntimeManagedDirectoryPolicy(
          customPath: _playbackCacheDir,
          bookmark: _playbackCacheDirBookmark,
        ),
        recordingDirectory: RuntimeManagedDirectoryPolicy(
          customPath: _recordingDir,
          bookmark: _recordingDirBookmark,
        ),
      );

  List<RssFeedConfig> _rssFeeds = _defaultRssFeeds();
  List<RssFeedConfig> get rssFeeds => List.unmodifiable(_rssFeeds);
  List<RssFeedConfig> get enabledRssFeeds => _rssFeeds
      .where((feed) => feed.enabled && feed.url.trim().isNotEmpty)
      .toList(growable: false);
  String get rssFeedSignature => _rssFeeds
      .map((feed) => '${feed.id}|${feed.enabled}|${feed.title}|${feed.url}')
      .join('||');

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
    final descriptor = sourceDescriptor(source);
    if (!descriptor.requiresLocalApiKey) {
      return true;
    }
    // 检查 credentialHints 中声明的所有凭证字段
    if (descriptor.credentialHints.isNotEmpty) {
      return descriptor.credentialHints.every(
        (hint) => (config.credentials[hint.credKey] ?? '').trim().isNotEmpty,
      );
    }
    // 回退：检查旧版 apiKey
    return config.apiKey.trim().isNotEmpty;
  }

  String sourceDisplayName(String source) {
    return sourceDescriptor(source).label;
  }

  String sourceSearchCapabilitySummary(String source) {
    final descriptor = sourceDescriptor(source);
    final localLabel = !descriptor.supportsLocalSearch
        ? '当前不支持'
        : isLocalSourceReady(source)
            ? '已就绪'
            : '待配置';
    final mediaTypes = <String>[
      if (descriptor.supportsVideo) '视频',
      if (descriptor.supportsAudio) '音频',
    ].join(' / ');
    return '媒体类型: $mediaTypes\n本地搜索: $localLabel';
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

  void setSourceCredential(String source, String credKey, String value) {
    final config = _sourceConfigs[source];
    if (config == null) {
      return;
    }
    config.credentials[credKey] = value;
    notifyListeners();
    unawaited(_persistSourceConfigs());
  }

  void setSourceCustomBaseUrl(String source, String url) {
    final config = _sourceConfigs[source];
    if (config == null) {
      return;
    }
    config.customBaseUrl = url;
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

  void setRecordingDir(String value) {
    setRuntimeRecordingDirSelection(value.trim(), bookmark: '');
  }

  void setRuntimeRecordingDirSelection(String path, {String bookmark = ''}) {
    _recordingDir = path.trim();
    _recordingDirBookmark = bookmark.trim();
    notifyListeners();
    unawaited(_writeSetting(_recordingDirKey, _recordingDir));
    unawaited(_writeSetting(_recordingDirBookmarkKey, _recordingDirBookmark));
  }

  void setRecordingDirSelection(String path, {String bookmark = ''}) {
    setRuntimeRecordingDirSelection(path, bookmark: bookmark);
  }

  void setPlaybackCacheEnabled(bool value) {
    setRuntimeProgressiveCacheEnabled(value);
  }

  void setRuntimeProgressiveCacheEnabled(bool value) {
    _playbackCacheEnabled = value;
    notifyListeners();
    unawaited(_writeSetting(_playbackCacheEnabledKey, value.toString()));
  }

  void setPlaybackCacheDir(String value) {
    setRuntimeCacheDirSelection(value.trim(), bookmark: '');
  }

  void setPlaybackCacheDirSelection(String path, {String bookmark = ''}) {
    setRuntimeCacheDirSelection(path, bookmark: bookmark);
  }

  void setRuntimeCacheDirSelection(String path, {String bookmark = ''}) {
    _playbackCacheDir = path.trim();
    _playbackCacheDirBookmark = bookmark.trim();
    notifyListeners();
    unawaited(_writeSetting(_playbackCacheDirKey, _playbackCacheDir));
    unawaited(
      _writeSetting(_playbackCacheDirBookmarkKey, _playbackCacheDirBookmark),
    );
  }

  void upsertRssFeed(RssFeedConfig feed) {
    final normalizedUrl = feed.url.trim();
    final normalizedTitle = feed.title.trim();
    if (normalizedUrl.isEmpty || normalizedTitle.isEmpty) {
      return;
    }
    final normalized = feed.copyWith(
      id: feed.id.trim().isEmpty ? _buildRssFeedId(normalizedTitle) : feed.id,
      title: normalizedTitle,
      url: normalizedUrl,
      subtitle: feed.subtitle.trim(),
    );
    final index = _rssFeeds.indexWhere((item) => item.id == normalized.id);
    if (index >= 0) {
      _rssFeeds[index] = normalized;
    } else {
      _rssFeeds = [..._rssFeeds, normalized];
    }
    notifyListeners();
    unawaited(_persistRssFeeds());
  }

  void removeRssFeed(String feedId) {
    _rssFeeds = _rssFeeds.where((feed) => feed.id != feedId).toList();
    notifyListeners();
    unawaited(_persistRssFeeds());
  }

  void setRssFeedEnabled(String feedId, bool enabled) {
    final index = _rssFeeds.indexWhere((feed) => feed.id == feedId);
    if (index < 0) {
      return;
    }
    _rssFeeds[index] = _rssFeeds[index].copyWith(enabled: enabled);
    notifyListeners();
    unawaited(_persistRssFeeds());
  }

  String exportRssFeedsJson() {
    final payload = {
      'version': 1,
      'feeds': _rssFeeds.map((feed) => feed.toJson()).toList(growable: false),
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  int importRssFeedsJson(String raw, {bool replace = false}) {
    final decoded = jsonDecode(raw);
    final incoming = _decodeRssFeedPayload(decoded);
    if (incoming.isEmpty) {
      return 0;
    }

    if (replace) {
      _rssFeeds = incoming;
    } else {
      final merged = <RssFeedConfig>[..._rssFeeds];
      for (final feed in incoming) {
        final index = merged.indexWhere(
          (item) => item.id == feed.id || item.url == feed.url,
        );
        if (index >= 0) {
          merged[index] = feed;
        } else {
          merged.add(feed);
        }
      }
      _rssFeeds = merged;
    }
    notifyListeners();
    unawaited(_persistRssFeeds());
    return incoming.length;
  }

  int addDefaultRssFeeds() {
    final before = _rssFeeds.length;
    importRssFeedsJson(
      jsonEncode(
        _defaultRssFeeds().map((feed) => feed.toJson()).toList(growable: false),
      ),
      replace: false,
    );
    return _rssFeeds.length - before;
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

      final savedRecordingDir = values[_recordingDirKey];
      if (savedRecordingDir != null) {
        _recordingDir = savedRecordingDir;
      }
      final savedRecordingDirBookmark = values[_recordingDirBookmarkKey];
      if (savedRecordingDirBookmark != null) {
        _recordingDirBookmark = savedRecordingDirBookmark;
      }

      final savedCacheEnabled = values[_playbackCacheEnabledKey];
      if (savedCacheEnabled != null) {
        _playbackCacheEnabled = savedCacheEnabled == 'true';
      }

      final savedCacheDir = values[_playbackCacheDirKey];
      if (savedCacheDir != null) {
        _playbackCacheDir = savedCacheDir;
      }
      final savedCacheDirBookmark = values[_playbackCacheDirBookmarkKey];
      if (savedCacheDirBookmark != null) {
        _playbackCacheDirBookmark = savedCacheDirBookmark;
      }

      final savedRssFeeds = values[_rssFeedsKey];
      if (savedRssFeeds != null && savedRssFeeds.isNotEmpty) {
        final decoded = jsonDecode(savedRssFeeds);
        if (decoded is List) {
          _rssFeeds = decoded
              .whereType<Map>()
              .map((item) => RssFeedConfig.fromJson(Map<String, dynamic>.from(item)))
              .where((item) => item.title.trim().isNotEmpty && item.url.trim().isNotEmpty)
              .toList(growable: true);
          if (_rssFeeds.isEmpty) {
            _rssFeeds = _defaultRssFeeds();
          }
        }
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

  Future<void> _persistRssFeeds() async {
    final payload = jsonEncode(
      _rssFeeds.map((feed) => feed.toJson()).toList(growable: false),
    );
    await _writeSetting(_rssFeedsKey, payload);
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

  static List<RssFeedConfig> _defaultRssFeeds() {
    return const [
      RssFeedConfig(
        id: 'feed.devto.flutter',
        title: 'DEV.to Flutter Feed',
        url: 'https://dev.to/feed/tag/flutter',
        subtitle: '实时 Flutter 文章 RSS',
      ),
      RssFeedConfig(
        id: 'feed.devto.dart',
        title: 'DEV.to Dart Feed',
        url: 'https://dev.to/feed/tag/dart',
        subtitle: '实时 Dart 文章 RSS',
      ),
      RssFeedConfig(
        id: 'feed.google.flutter',
        title: 'Google News Flutter RSS',
        url:
            'https://news.google.com/rss/search?q=flutter&hl=zh-CN&gl=CN&ceid=CN:zh-Hans',
        subtitle: 'Flutter 新闻聚合',
      ),
      RssFeedConfig(
        id: 'feed.sspai',
        title: '少数派',
        url: 'https://sspai.com/feed',
        subtitle: '中文科技与效率内容',
      ),
      RssFeedConfig(
        id: 'feed.ruanyifeng',
        title: '阮一峰网络日志',
        url: 'https://www.ruanyifeng.com/blog/atom.xml',
        subtitle: '开发者常读周刊与技术随笔',
      ),
      RssFeedConfig(
        id: 'feed.v2ex',
        title: 'V2EX',
        url: 'https://www.v2ex.com/index.xml',
        subtitle: '中文社区热门讨论',
      ),
      RssFeedConfig(
        id: 'feed.hackernews',
        title: 'Hacker News',
        url: 'https://news.ycombinator.com/rss',
        subtitle: '全球技术资讯热门源',
      ),
      RssFeedConfig(
        id: 'feed.infoq',
        title: 'InfoQ 中文',
        url: 'https://www.infoq.cn/feed.xml',
        subtitle: '中文技术媒体 RSS',
      ),
    ];
  }

  static String _buildRssFeedId(String title) {
    final normalized = title
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    final prefix = normalized.isEmpty ? 'rss_feed' : normalized;
    return '$prefix-${DateTime.now().microsecondsSinceEpoch}';
  }

  static List<RssFeedConfig> _decodeRssFeedPayload(Object? decoded) {
    final rawList = switch (decoded) {
      final List<dynamic> list => list,
      final Map<dynamic, dynamic> map when map['feeds'] is List => map['feeds'] as List,
      _ => const <dynamic>[],
    };
    return rawList
        .whereType<Map>()
        .map((item) => RssFeedConfig.fromJson(Map<String, dynamic>.from(item)))
        .where((item) => item.title.trim().isNotEmpty && item.url.trim().isNotEmpty)
        .toList(growable: false);
  }
}
