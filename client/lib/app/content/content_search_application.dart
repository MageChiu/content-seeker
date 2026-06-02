import '../../core/source_catalog.dart';
import '../../core/local_source_registry.dart';
import '../../core/content/content_ports.dart';
import '../../domain/content/content_models.dart';
import '../../features/settings/settings_provider.dart';
import '../../features/search/sources/server_source.dart';
import 'legacy_content_search_bridge.dart';

class ContentSearchExecutionResult {
  final CursorPage<ContentSearchResult> page;
  final String? errorMessage;

  const ContentSearchExecutionResult({
    required this.page,
    this.errorMessage,
  });
}

class ContentSearchApplication {
  final Map<String, SearchSourceFactory> localSourceRegistry;
  final List<ContentSearchPort> additionalPorts;

  ContentSearchApplication({
    Map<String, SearchSourceFactory>? localSourceRegistry,
    List<ContentSearchPort>? additionalPorts,
  })  : localSourceRegistry = localSourceRegistry ?? kLocalSourceRegistry,
        additionalPorts = additionalPorts ?? const [];

  Future<ContentSearchExecutionResult> search(
    ContentSearchRequest request, {
    required SettingsProvider settings,
  }) {
    switch (settings.searchStrategy) {
      case SearchStrategy.preferRemote:
        return _searchPreferRemote(request, settings);
      case SearchStrategy.preferLocal:
        return _searchPreferLocal(request, settings);
      case SearchStrategy.localOnly:
        return _searchLocal(
          request,
          settings,
          surfaceStrategyErrors: true,
        );
      case SearchStrategy.remoteOnly:
        return _searchRemote(
          request,
          settings,
          surfaceStrategyErrors: true,
        );
    }
  }

  Future<ContentSearchExecutionResult> _searchPreferRemote(
    ContentSearchRequest request,
    SettingsProvider settings,
  ) async {
    final remote = await _searchRemote(
      request,
      settings,
      surfaceStrategyErrors: false,
    );
    if (remote.page.items.isNotEmpty) {
      return remote;
    }
    return _searchLocal(
      request,
      settings,
      surfaceStrategyErrors: false,
    );
  }

  Future<ContentSearchExecutionResult> _searchPreferLocal(
    ContentSearchRequest request,
    SettingsProvider settings,
  ) async {
    final local = await _searchLocal(
      request,
      settings,
      surfaceStrategyErrors: false,
    );
    if (local.page.items.isNotEmpty) {
      return local;
    }
    return _searchRemote(
      request,
      settings,
      surfaceStrategyErrors: false,
    );
  }

  Future<ContentSearchExecutionResult> _searchLocal(
    ContentSearchRequest request,
    SettingsProvider settings, {
    required bool surfaceStrategyErrors,
  }) async {
    final futures = <Future<CursorPage<ContentSearchResult>>>[];
    final supplementalPages = await _searchAdditionalPorts(request);

    for (final sourceId in settings.enabledLocalSources) {
      if (!_supportsRequestedTypes(sourceId, request.types)) {
        continue;
      }
      if (!settings.isLocalSourceReady(sourceId)) {
        continue;
      }
      final factory = localSourceRegistry[sourceId];
      if (factory == null) {
        continue;
      }
      final config = settings.sourceConfigs[sourceId];
      if (config == null) {
        continue;
      }
      final port = LegacySearchSourceContentSearchPort(
        adapterId: 'legacy.local.$sourceId',
        source: factory(config),
      );
      futures.add(port.search(request));
    }

    if (futures.isEmpty) {
      final supplemental = _mergePages(supplementalPages);
      if (supplemental.items.isNotEmpty) {
        return ContentSearchExecutionResult(page: supplemental);
      }
      return ContentSearchExecutionResult(
        page: const CursorPage(items: []),
        errorMessage: surfaceStrategyErrors
            ? '当前没有可用的本地搜索源，请先在设置中启用并完成配置。'
            : null,
      );
    }

    final pages = await Future.wait(futures);
    return ContentSearchExecutionResult(
      page: _mergePages([
        ...pages,
        ...supplementalPages,
      ]),
    );
  }

  Future<ContentSearchExecutionResult> _searchRemote(
    ContentSearchRequest request,
    SettingsProvider settings, {
    required bool surfaceStrategyErrors,
  }) async {
    final supplementalPages = await _searchAdditionalPorts(request);
    final sources = settings.enabledRemoteSearchSources;
    if (sources.isEmpty) {
      final supplemental = _mergePages(supplementalPages);
      if (supplemental.items.isNotEmpty) {
        return ContentSearchExecutionResult(page: supplemental);
      }
      return ContentSearchExecutionResult(
        page: const CursorPage(items: []),
        errorMessage: surfaceStrategyErrors ? '当前没有启用可用的远程内容源。' : null,
      );
    }

    if (!settings.canUseRemoteSearch) {
      final supplemental = _mergePages(supplementalPages);
      if (supplemental.items.isNotEmpty) {
        return ContentSearchExecutionResult(page: supplemental);
      }
      return ContentSearchExecutionResult(
        page: const CursorPage(items: []),
        errorMessage: surfaceStrategyErrors ? '远程搜索未配置服务端地址。' : null,
      );
    }

    final port = LegacyServerContentSearchPort(
      adapterId: 'legacy.remote.server',
      source: ServerSearchSource(baseUrl: settings.serverUrl),
      sources: sources,
      enableWebSupplement: settings.isRemoteSourceEnabled('google'),
    );
    final page = await port.search(request);
    return ContentSearchExecutionResult(
      page: _mergePages([page, ...supplementalPages]),
    );
  }

  CursorPage<ContentSearchResult> _mergePages(
    List<CursorPage<ContentSearchResult>> pages,
  ) {
    return CursorPage(
      items: pages.expand((page) => page.items).toList(growable: false),
    );
  }

  Future<List<CursorPage<ContentSearchResult>>> _searchAdditionalPorts(
    ContentSearchRequest request,
  ) {
    if (additionalPorts.isEmpty) {
      return Future.value(const []);
    }
    return Future.wait(
      additionalPorts.map((port) => port.search(request)),
    );
  }

  bool _supportsRequestedTypes(String sourceId, Set<ContentType> types) {
    if (types.isEmpty) {
      return true;
    }
    final descriptor = sourceDescriptor(sourceId);
    if (types.contains(ContentType.audio) && descriptor.supportsAudio) {
      return true;
    }
    if (types.contains(ContentType.video) && descriptor.supportsVideo) {
      return true;
    }
    return false;
  }
}
