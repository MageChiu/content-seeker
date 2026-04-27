// 搜索编排 Provider：路由 + 合并 + 状态管理
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import '../../app/content/content_search_application.dart';
import '../../app/content/legacy_content_search_bridge.dart';
import '../../domain/content/content_models.dart' as unified_content;
import '../../core/source_catalog.dart';
import '../../core/search_source.dart';
import '../../core/local_source_registry.dart';
import '../../models/search_result.dart';
import '../settings/settings_provider.dart';
import 'local_llm_service.dart';
import 'sources/server_source.dart';

// #region debug-point B:provider-state
void _debugReportSearchProvider(
  String hypothesisId,
  String location,
  String msg,
  Map<String, dynamic> data,
) {
  final client = HttpClient();
  unawaited(() async {
    try {
      final request =
          await client.postUrl(Uri.parse('http://127.0.0.1:7777/event'));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'sessionId': 'local-bilibili-search',
        'runId': 'pre-fix',
        'hypothesisId': hypothesisId,
        'location': location,
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

class SearchProvider extends ChangeNotifier {
  final ContentSearchApplication? _contentSearchApplication;
  SettingsProvider? _settings;
  List<SearchResult> _results = [];
  bool _loading = false;
  String? _error;
  String _lastQuery = '';
  MediaType? _mediaTypeFilter;
  bool _readingOnly = false;
  bool _localLlmOptimized = false;
  bool _localLlmRewriteApplied = false;
  bool _localLlmRerankApplied = false;
  int _localLlmSummaryCount = 0;

  List<SearchResult> get results => _results;
  bool get loading => _loading;
  String? get error => _error;
  String get lastQuery => _lastQuery;
  MediaType? get mediaTypeFilter => _mediaTypeFilter;
  bool get readingOnly => _readingOnly;
  bool get localLlmOptimized => _localLlmOptimized;
  bool get localLlmRewriteApplied => _localLlmRewriteApplied;
  bool get localLlmRerankApplied => _localLlmRerankApplied;
  int get localLlmSummaryCount => _localLlmSummaryCount;

  SearchProvider({
    ContentSearchApplication? contentSearchApplication,
  }) : _contentSearchApplication = contentSearchApplication;

  void updateSettings(SettingsProvider settings) {
    _settings = settings;
  }

  void setSearchFilter({
    MediaType? mediaType,
    bool readingOnly = false,
  }) {
    if (_mediaTypeFilter == mediaType && _readingOnly == readingOnly) {
      return;
    }
    _mediaTypeFilter = mediaType;
    _readingOnly = readingOnly;
    notifyListeners();
  }

  void setMediaTypeFilter(MediaType? value) {
    setSearchFilter(mediaType: value, readingOnly: false);
  }

  Future<void> search(
    String query, {
    MediaType? mediaTypeFilter,
    bool readingOnly = false,
  }) async {
    if (query.trim().isEmpty) return;

    _mediaTypeFilter = mediaTypeFilter;
    _readingOnly = readingOnly;
    _lastQuery = query;
    _loading = true;
    _error = null;
    _results = [];
    _localLlmOptimized = false;
    _localLlmRewriteApplied = false;
    _localLlmRerankApplied = false;
    _localLlmSummaryCount = 0;
    notifyListeners();

    try {
      final settings = _settings;
      // #region debug-point B:search-start
      _debugReportSearchProvider(
          'B', 'search_provider.dart:search:start', 'provider search start', {
        'query': query,
        'strategy': settings?.searchStrategy.name,
        'mediaTypeFilter': _mediaTypeFilter?.name,
        'readingOnly': _readingOnly,
        'settingsReady': settings != null,
      });
      // #endregion
      if (settings == null) {
        return;
      }

      final localLlm = LocalLlmService(settings: settings);
      final rewriteResult = await localLlm.rewriteQuery(
        query,
        mediaTypeFilter: _mediaTypeFilter,
      );
      final rewrittenQuery = rewriteResult.effectiveQuery;
      final effectiveQuery = rewrittenQuery != null && rewrittenQuery.isNotEmpty
          ? rewrittenQuery
          : query;
      _localLlmRewriteApplied = rewriteResult.applied;

      _debugReportSearchProvider(
        'L',
        'search_provider.dart:search:rewrite',
        'local llm rewrite resolved',
        {
          'query': query,
          'effectiveQuery': effectiveQuery,
          'rewritten': rewrittenQuery,
          'rewriteApplied': _localLlmRewriteApplied,
          'readingOnly': _readingOnly,
          'localLlmReady': localLlm.isReady,
        },
      );

      final merged = await _searchWithPreferredBoundary(
        effectiveQuery,
        settings,
        mediaTypeFilter: _mediaTypeFilter,
      );

      // 去重
      final seen = <String>{};
      _results = merged.where((r) {
        final key = '${r.source}_${r.id}';
        return seen.add(key);
      }).toList();

      // 按源统计结果分布
      final sourceDistribution = <String, int>{};
      for (final r in _results) {
        sourceDistribution[r.source] =
            (sourceDistribution[r.source] ?? 0) + 1;
      }

      // #region debug-point D:search-merged
      _debugReportSearchProvider('D', 'search_provider.dart:search:merged',
          'provider merged results', {
        'rawCount': merged.length,
        'dedupedCount': _results.length,
        'sourceDistribution': sourceDistribution,
        'error': _error,
      });
      // #endregion

      _results.sort(_compareResults);
      final rerankResult = await localLlm.rerankResults(
        query,
        _results,
        mediaTypeFilter: _mediaTypeFilter,
      );
      _results = rerankResult.results;
      _localLlmRerankApplied = rerankResult.applied;

      _debugReportSearchProvider(
        'L',
        'search_provider.dart:search:rerank',
        'local llm rerank resolved',
        {
          'query': query,
          'resultCount': _results.length,
          'rerankApplied': _localLlmRerankApplied,
          'readingOnly': _readingOnly,
        },
      );

      final summaryResult = await localLlm.summarizeResults(
        query,
        _results,
        mediaTypeFilter: _mediaTypeFilter,
      );
      _results = summaryResult.results;
      _localLlmSummaryCount = summaryResult.summaryCount;
      _localLlmOptimized = _localLlmRewriteApplied ||
          _localLlmRerankApplied ||
          _localLlmSummaryCount > 0;
    } catch (e) {
      _error = '搜索失败: $e';
      // #region debug-point E:provider-error
      _debugReportSearchProvider('E', 'search_provider.dart:search:catch',
          'provider search exception', {
        'query': query,
        'error': e.toString(),
      });
      // #endregion
    } finally {
      _loading = false;
      // #region debug-point E:provider-final
      _debugReportSearchProvider(
          'E', 'search_provider.dart:search:finally', 'provider final state', {
        'loading': _loading,
        'error': _error,
        'resultCount': _results.length,
        'lastQuery': _lastQuery,
        'localLlmOptimized': _localLlmOptimized,
        'rewriteApplied': _localLlmRewriteApplied,
        'rerankApplied': _localLlmRerankApplied,
        'summaryCount': _localLlmSummaryCount,
      });
      // #endregion
      notifyListeners();
    }
  }

  Future<List<SearchResult>> _searchWithPreferredBoundary(
    String query,
    SettingsProvider settings, {
    MediaType? mediaTypeFilter,
  }) async {
    final boundary = _contentSearchApplication;
    if (boundary == null) {
      return _searchWithLegacyStrategy(
        query,
        settings,
        mediaTypeFilter: mediaTypeFilter,
      );
    }

    try {
      final request = unified_content.ContentSearchRequest(
        query: query,
        types: _toContentTypes(mediaTypeFilter),
      );
      _debugReportSearchProvider(
        'B',
        'search_provider.dart:_searchWithPreferredBoundary:start',
        'searching through unified content boundary',
        {
          'query': query,
          'strategy': settings.searchStrategy.name,
          'mediaTypeFilter': mediaTypeFilter?.name,
        'readingOnly': _readingOnly,
          'requestTypes': request.types.map((item) => item.name).toList(),
        },
      );
      final result = await boundary.search(request, settings: settings);
      _error = result.errorMessage;
      final items = result.page.items
          .map((item) => item.toLegacySearchResult())
          .toList(growable: false);
      _debugReportSearchProvider(
        'D',
        'search_provider.dart:_searchWithPreferredBoundary:done',
        'unified content boundary completed',
        {
          'query': query,
          'resultCount': items.length,
          'error': _error,
        },
      );
      return items;
    } catch (e) {
      _debugReportSearchProvider(
        'W',
        'search_provider.dart:_searchWithPreferredBoundary:fallback',
        'unified content boundary failed, fallback to legacy search',
        {
          'query': query,
          'error': e.toString(),
        },
      );
      return _searchWithLegacyStrategy(
        query,
        settings,
        mediaTypeFilter: mediaTypeFilter,
      );
    }
  }

  Future<List<SearchResult>> _searchWithLegacyStrategy(
    String query,
    SettingsProvider settings, {
    MediaType? mediaTypeFilter,
  }) {
    switch (settings.searchStrategy) {
      case SearchStrategy.preferRemote:
        return _searchPreferRemote(
          query,
          settings,
          mediaTypeFilter: mediaTypeFilter,
        );
      case SearchStrategy.preferLocal:
        return _searchPreferLocal(
          query,
          settings,
          mediaTypeFilter: mediaTypeFilter,
        );
      case SearchStrategy.localOnly:
        return _searchLocal(
          query,
          settings,
          mediaTypeFilter: mediaTypeFilter,
        );
      case SearchStrategy.remoteOnly:
        return _searchRemote(
          query,
          settings,
          mediaTypeFilter: mediaTypeFilter,
        );
    }
  }

  Future<List<SearchResult>> _searchPreferRemote(
      String query, SettingsProvider settings,
      {MediaType? mediaTypeFilter}) async {
    final remoteResults = await _searchRemote(
      query,
      settings,
      mediaTypeFilter: mediaTypeFilter,
    );
    if (remoteResults.isNotEmpty) {
      return remoteResults;
    }
    return _searchLocal(
      query,
      settings,
      mediaTypeFilter: mediaTypeFilter,
    );
  }

  Future<List<SearchResult>> _searchPreferLocal(
      String query, SettingsProvider settings,
      {MediaType? mediaTypeFilter}) async {
    final localResults = await _searchLocal(
      query,
      settings,
      mediaTypeFilter: mediaTypeFilter,
    );
    if (localResults.isNotEmpty) {
      return localResults;
    }
    return _searchRemote(
      query,
      settings,
      mediaTypeFilter: mediaTypeFilter,
    );
  }

  Future<List<SearchResult>> _searchLocal(
      String query, SettingsProvider settings,
      {MediaType? mediaTypeFilter}) async {
    final futures = <Future<List<SearchResult>>>[];
    final readiness = <String, bool>{};
    final skippedSources = <String, String>{};

    for (final source in settings.enabledLocalSources) {
      final descriptor = sourceDescriptor(source);
      if (mediaTypeFilter == MediaType.video && !descriptor.supportsVideo) {
        skippedSources[source] = 'mediaType filter: video, source has no video';
        continue;
      }
      if (mediaTypeFilter == MediaType.audio && !descriptor.supportsAudio) {
        skippedSources[source] = 'mediaType filter: audio, source has no audio';
        continue;
      }

      final ready = settings.isLocalSourceReady(source);
      readiness[source] = ready;
      if (!ready) {
        skippedSources[source] = 'not ready (missing credentials or disabled)';
        continue;
      }

      final factory = kLocalSourceRegistry[source];
      if (factory == null) {
        skippedSources[source] = 'no factory registered in kLocalSourceRegistry';
        _debugReportSearchProvider(
          'W',
          'search_provider.dart:_searchLocal',
          'source has no registered factory',
          {'source': source},
        );
        continue;
      }
      final config = settings.sourceConfigs[source]!;
      _debugReportSearchProvider(
        'B',
        'search_provider.dart:_searchLocal:dispatch',
        'dispatching local source',
        {
          'source': source,
          'query': query,
          'hasCredentials': config.credentials.isNotEmpty,
          'customBaseUrl': config.customBaseUrl,
          'stabilityTier': descriptor.stabilityTier.name,
          'region': descriptor.region.name,
        },
      );
      futures.add(
        _runLocalSource(source, factory(config), query),
      );
    }

    // #region debug-point B:local-readiness
    _debugReportSearchProvider(
        'B', 'search_provider.dart:_searchLocal', 'local source readiness', {
      'query': query,
      'strategy': settings.searchStrategy.name,
      'mediaTypeFilter': mediaTypeFilter?.name,
      'enabledSources': settings.enabledLocalSources,
      'readySources': settings.readyLocalSources,
      'readiness': readiness,
      'skippedSources': skippedSources,
      'futureCount': futures.length,
    });
    // #endregion

    if (futures.isEmpty) {
      if (settings.searchStrategy == SearchStrategy.localOnly) {
        _error = '当前没有可用的本地搜索源，请先在设置中启用并完成配置。';
      }
      return [];
    }

    final results = await Future.wait(futures);
    // #region debug-point D:local-results
    _debugReportSearchProvider('D', 'search_provider.dart:_searchLocal:done',
        'local search futures completed', {
      'sourceCount': results.length,
      'itemCounts': results.map((items) => items.length).toList(),
    });
    // #endregion
    return _applyMediaTypeFilter(
      results.expand((items) => items).toList(),
      mediaTypeFilter,
    );
  }

  Future<List<SearchResult>> _searchRemote(
      String query, SettingsProvider settings,
      {MediaType? mediaTypeFilter}) async {
    final sources = settings.enabledRemoteSearchSources;
    if (sources.isEmpty) {
      if (settings.searchStrategy == SearchStrategy.remoteOnly) {
        _error = '当前没有启用可用的远程内容源。';
      }
      return [];
    }

    if (!settings.canUseRemoteSearch) {
      if (settings.searchStrategy == SearchStrategy.remoteOnly) {
        _error = '远程搜索未配置服务端地址。';
      }
      return [];
    }

    return _searchViaServer(
      query,
      sources: sources,
      mediaTypeFilter: mediaTypeFilter,
      enableWebSupplement: settings.isRemoteSourceEnabled('google'),
    );
  }

  Future<List<SearchResult>> _searchViaServer(
    String query, {
    required List<String> sources,
    MediaType? mediaTypeFilter,
    required bool enableWebSupplement,
  }) async {
    try {
      final serverUrl = _settings?.serverUrl ?? 'http://localhost:8000';
      final source = ServerSearchSource(baseUrl: serverUrl);
      return await source.search(
        query,
        sources: sources,
        mediaTypePreference: _toSearchIntent(mediaTypeFilter),
        enableWebSupplement: enableWebSupplement,
      );
    } catch (_) {
      return [];
    }
  }

  List<SearchResult> _applyMediaTypeFilter(
    List<SearchResult> results,
    MediaType? mediaTypeFilter,
  ) {
    if (mediaTypeFilter == null) {
      return results;
    }
    return results
        .where((result) => result.mediaType == mediaTypeFilter)
        .toList(growable: false);
  }

  String? _toSearchIntent(MediaType? mediaTypeFilter) {
    switch (mediaTypeFilter) {
      case MediaType.video:
        return 'video';
      case MediaType.audio:
        return 'audio';
      case null:
        return null;
    }
  }

  Set<unified_content.ContentType> _toContentTypes(MediaType? mediaTypeFilter) {
    if (_readingOnly) {
      return const {
        unified_content.ContentType.webArticle,
        unified_content.ContentType.rss,
        unified_content.ContentType.novel,
      };
    }
    switch (mediaTypeFilter) {
      case MediaType.audio:
        return const {unified_content.ContentType.audio};
      case MediaType.video:
        return const {unified_content.ContentType.video};
      case null:
        return const {};
    }
  }

  int _compareResults(SearchResult a, SearchResult b) {
    final scoreA = _scoreResult(a);
    final scoreB = _scoreResult(b);
    if (scoreA != scoreB) {
      return scoreB.compareTo(scoreA);
    }
    return a.title.compareTo(b.title);
  }

  int _scoreResult(SearchResult result) {
    var score = 0;

    switch (result.sourceTier) {
      case SourceTier.officialApi:
        score += 30;
      case SourceTier.publicApi:
        score += 20;
      case SourceTier.webSupplement:
        score += 10;
    }

    if (result.isPlayable) {
      score += 15;
    }

    switch (result.availability) {
      case ResultAvailability.available:
        score += 10;
      case ResultAvailability.preview:
        score += 6;
      case ResultAvailability.indexedOnly:
        score += 1;
    }

    switch (result.playbackKind) {
      case SearchPlaybackKind.nativeStream:
        score += 8;
      case SearchPlaybackKind.embeddedWeb:
        score += 4;
      case SearchPlaybackKind.externalOpen:
        score += 1;
    }

    if (result.thumbnailUrl.isNotEmpty) score += 2;
    if (result.durationSeconds > 0) score += 2;
    if (result.hasArtistOrAuthor) score += 2;
    if (result.hasAlbumOrSeries) score += 2;
    if (result.hasAiSummary) score += 2;
    if (result.hasHighlights) score += 1;
    if (result.isReadingResult) {
      score += 12;
      if (result.supportsSave) {
        score += 4;
      }
    }
    if (_readingOnly && result.isReadingResult) {
      score += 25;
    }

    if (_mediaTypeFilter != null && result.mediaType == _mediaTypeFilter) {
      score += 20;
    }

    if (_mediaTypeFilter == MediaType.audio) {
      switch (result.mediaSubtype) {
        case MediaSubtype.musicTrack:
          score += 8;
        case MediaSubtype.podcastEpisode:
          score += 2;
        case MediaSubtype.podcastShow:
          score += 1;
        case MediaSubtype.video:
          break;
      }
      if (result.source == 'itunes' || result.source == 'jamendo') {
        score += 10;
      }
      if (result.source == 'deezer' || result.source == 'internet_archive') {
        score += 8;
      }
    }

    if (_mediaTypeFilter == MediaType.video &&
        result.mediaSubtype == MediaSubtype.video) {
      score += 8;
      if (result.source == 'dailymotion' ||
          result.source == 'internet_archive_video') {
        score += 6;
      }
      if (result.source == 'vimeo' || result.source == 'peertube') {
        score += 6;
      }
      if (result.source == 'acfun' || result.source == 'youku') {
        score += 4;
      }
    }

    return score;
  }

  Future<List<SearchResult>> _runLocalSource(
    String sourceName,
    SearchSource source,
    String query,
  ) async {
    final stopwatch = Stopwatch()..start();
    _debugReportSearchProvider(
      'B',
      'search_provider.dart:_runLocalSource:start',
      'local source search started',
      {
        'source': sourceName,
        'query': query,
        'isConfigured': source.isConfigured,
      },
    );
    try {
      final results = await source.search(query);
      stopwatch.stop();
      _debugReportSearchProvider(
        'D',
        'search_provider.dart:_runLocalSource:done',
        'local source search completed',
        {
          'source': sourceName,
          'query': query,
          'resultCount': results.length,
          'elapsedMs': stopwatch.elapsedMilliseconds,
          'firstResultTitle':
              results.isNotEmpty ? results.first.title : null,
        },
      );
      return results;
    } catch (e) {
      stopwatch.stop();
      _debugReportSearchProvider(
        'E',
        'search_provider.dart:_runLocalSource',
        'local source failed',
        {
          'source': sourceName,
          'query': query,
          'error': e.toString(),
          'elapsedMs': stopwatch.elapsedMilliseconds,
          'errorType': e.runtimeType.toString(),
        },
      );
      return const [];
    }
  }
}
