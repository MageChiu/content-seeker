import '../content/content_engine.dart';
import '../content/content_detail_fallback_port.dart';
import '../content/content_reader_application.dart';
import '../content/content_search_application.dart';
import '../content/runtime_content_ports.dart';
import '../../platform/capabilities/platform_capability_service.dart';
import '../../platform/storage/app_storage_paths.dart';
import '../../infra/download/json_offline_asset_repository.dart';
import '../../infra/download/offline_asset_repository.dart';
import '../../infra/content/persistent_content_store.dart';
import '../../infra/content/real_reading_source_hub.dart';
import '../download/download_coordinator.dart';
import '../feature_flags/feature_registry.dart';
import '../runtime/runtime_coordinator.dart';
import '../../features/settings/settings_provider.dart';
import 'app_environment.dart';

class DependencyContainer {
  final AppEnvironment environment;
  final DownloadCoordinator downloadCoordinator;
  final RuntimeCoordinator runtimeCoordinator;
  final FeatureRegistry featureRegistry;
  final ContentEngine contentEngine;
  final ContentSearchApplication contentSearchApplication;
  final OfflineAssetRepository offlineAssetRepository;
  final PersistentContentStore contentStore;
  final RealReadingSourceHub realReadingSourceHub;
  final ContentReaderApplication contentReaderApplication;

  const DependencyContainer({
    required this.environment,
    required this.downloadCoordinator,
    required this.runtimeCoordinator,
    required this.featureRegistry,
    required this.contentEngine,
    required this.contentSearchApplication,
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
    final downloadCoordinator = DownloadCoordinator(
      settingsProvider: settingsProvider,
    );
    final runtimeCoordinator = RuntimeCoordinator(
      settingsProvider: settingsProvider,
    );

    return DependencyContainer(
      environment: resolvedEnvironment,
      downloadCoordinator: downloadCoordinator,
      runtimeCoordinator: runtimeCoordinator,
      featureRegistry: FeatureRegistry(
        capabilities: capabilities,
        policy: resolvedEnvironment.featurePolicy,
      ),
      contentSearchApplication: ContentSearchApplication(
        additionalPorts: [realReadingSourceHub],
      ),
      contentEngine: ContentEngine(
        playbackPort: RuntimeContentPlaybackPort(
          settingsProvider: settingsProvider,
        ),
        downloadPort: RuntimeContentDownloadPort(
          downloadCoordinator: downloadCoordinator,
        ),
      ),
      offlineAssetRepository: offlineAssetRepository,
      contentStore: contentStore,
      realReadingSourceHub: realReadingSourceHub,
      contentReaderApplication: contentReaderApplication,
    );
  }
}
