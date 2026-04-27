import '../content/content_engine.dart';
import '../content/content_detail_fallback_port.dart';
import '../content/content_reader_application.dart';
import '../content/content_search_application.dart';
import '../content/legacy_content_ports.dart';
import '../../platform/capabilities/platform_capability_service.dart';
import '../../platform/storage/app_storage_paths.dart';
import '../../infra/resolver/legacy_playback_resolver_strategy.dart';
import '../../infra/resolver/resolver_orchestrator.dart';
import '../../infra/download/default_download_storage_manager.dart';
import '../../infra/download/download_engine.dart';
import '../../infra/download/download_repository.dart';
import '../../infra/download/download_storage_manager.dart';
import '../../infra/download/http_download_engine.dart';
import '../../infra/download/json_download_repository.dart';
import '../../infra/download/json_offline_asset_repository.dart';
import '../../infra/download/offline_asset_repository.dart';
import '../../infra/content/persistent_content_store.dart';
import '../../infra/content/real_reading_source_hub.dart';
import '../download/download_coordinator.dart';
import '../feature_flags/feature_registry.dart';
import '../playback/playback_coordinator.dart';
import '../../features/settings/settings_provider.dart';
import 'app_environment.dart';

class DependencyContainer {
  final AppEnvironment environment;
  final PlaybackCoordinator playbackCoordinator;
  final DownloadCoordinator downloadCoordinator;
  final FeatureRegistry featureRegistry;
  final ContentEngine contentEngine;
  final ContentSearchApplication contentSearchApplication;
  final ResolverOrchestrator resolverOrchestrator;
  final DownloadRepository downloadRepository;
  final DownloadStorageManager downloadStorageManager;
  final DownloadEngine downloadEngine;
  final OfflineAssetRepository offlineAssetRepository;
  final PersistentContentStore contentStore;
  final RealReadingSourceHub realReadingSourceHub;
  final ContentReaderApplication contentReaderApplication;

  const DependencyContainer({
    required this.environment,
    required this.playbackCoordinator,
    required this.downloadCoordinator,
    required this.featureRegistry,
    required this.contentEngine,
    required this.contentSearchApplication,
    required this.resolverOrchestrator,
    required this.downloadRepository,
    required this.downloadStorageManager,
    required this.downloadEngine,
    required this.offlineAssetRepository,
    required this.contentStore,
    required this.realReadingSourceHub,
    required this.contentReaderApplication,
  });

  factory DependencyContainer.bootstrap({
    AppEnvironment? environment,
    SettingsProvider? settingsProvider,
  }) {
    final resolvedEnvironment =
        environment ?? AppEnvironment.defaultEnvironment();
    final capabilities = createPlatformCapabilityService().current();
    const storagePaths = AppStoragePaths();
    final offlineAssetRepository = JsonOfflineAssetRepository(
      storagePaths: storagePaths,
    );
    final downloadRepository = JsonDownloadRepository(
      storagePaths: storagePaths,
    );
    const downloadStorageManager = DefaultDownloadStorageManager(
      storagePaths: storagePaths,
    );
    final downloadEngine = HttpDownloadEngine(
      offlineAssetRepository: offlineAssetRepository,
    );
    final contentStore = PersistentContentStore(
      storagePaths: storagePaths,
      offlineAssetRepository: offlineAssetRepository,
    );
    final realReadingSourceHub = RealReadingSourceHub(
      settingsProvider: settingsProvider,
    );
    final contentReaderApplication = ContentReaderApplication(
      featuredItemsLoader: realReadingSourceHub.featuredItemsSnapshot,
      detailPort: ContentDetailFallbackPort(
        ports: [contentStore, realReadingSourceHub],
      ),
      openPort: realReadingSourceHub,
      savePort: contentStore,
      libraryPort: contentStore,
      subscriptionPort: contentStore,
    );
    final playbackCoordinator = PlaybackCoordinator();
    final downloadCoordinator = DownloadCoordinator(
      repository: downloadRepository,
      storageManager: downloadStorageManager,
      downloadEngine: downloadEngine,
      offlineAssetRepository: offlineAssetRepository,
    );
    const resolverOrchestrator = ResolverOrchestrator(
      strategies: [LegacyPlaybackResolverStrategy()],
    );

    return DependencyContainer(
      environment: resolvedEnvironment,
      playbackCoordinator: playbackCoordinator,
      downloadCoordinator: downloadCoordinator,
      featureRegistry: FeatureRegistry(
        capabilities: capabilities,
        policy: resolvedEnvironment.featurePolicy,
      ),
      contentSearchApplication: ContentSearchApplication(
        additionalPorts: [realReadingSourceHub],
      ),
      contentEngine: ContentEngine(
        playbackPort: LegacyContentPlaybackPort(
          playbackCoordinator: playbackCoordinator,
          resolverOrchestrator: resolverOrchestrator,
        ),
        downloadPort: LegacyContentDownloadPort(
          downloadCoordinator: downloadCoordinator,
        ),
      ),
      resolverOrchestrator: resolverOrchestrator,
      downloadRepository: downloadRepository,
      downloadStorageManager: downloadStorageManager,
      downloadEngine: downloadEngine,
      offlineAssetRepository: offlineAssetRepository,
      contentStore: contentStore,
      realReadingSourceHub: realReadingSourceHub,
      contentReaderApplication: contentReaderApplication,
    );
  }
}
