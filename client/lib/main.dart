import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'app/bootstrap/app_bootstrap.dart';
import 'app/download/download_coordinator.dart';
import 'app/feature_flags/feature_registry.dart';
import 'features/reader/reader_provider.dart';
import 'features/search/search_provider.dart';
import 'features/search/search_page.dart';
import 'features/settings/settings_provider.dart';
import 'native_bridge/seeker_native.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  // 初始化 libseeker 原生核心
  try {
    final seeker = SeekerNative.instance;
    seeker.init();
    debugPrint('[libseeker] version ${seeker.version} initialized');
    debugPrint('[libseeker] supported sites: ${seeker.supportedSites}');
  } catch (e) {
    debugPrint('[libseeker] init failed: $e');
  }

  runApp(ContentSeekerApp());
}

class ContentSeekerApp extends StatelessWidget {
  final AppBootstrap bootstrap;
  final SettingsProvider settingsProvider;

  factory ContentSeekerApp({
    Key? key,
    AppBootstrap? bootstrap,
    SettingsProvider? settingsProvider,
  }) {
    final resolvedSettings = settingsProvider ?? SettingsProvider();
    final resolvedBootstrap =
        bootstrap ?? AppBootstrap.create(settingsProvider: resolvedSettings);
    resolvedBootstrap.container.realReadingSourceHub.attachSettings(
      resolvedSettings,
    );
    unawaited(resolvedBootstrap.container.downloadCoordinator.loadTasks());
    return ContentSeekerApp._(
      key: key,
      bootstrap: resolvedBootstrap,
      settingsProvider: resolvedSettings,
    );
  }

  const ContentSeekerApp._({
    super.key,
    required this.bootstrap,
    required this.settingsProvider,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AppBootstrap>.value(value: bootstrap),
        Provider<FeatureRegistry>.value(
            value: bootstrap.container.featureRegistry),
        ChangeNotifierProvider<SettingsProvider>.value(value: settingsProvider),
        ChangeNotifierProvider<DownloadCoordinator>.value(
          value: bootstrap.container.downloadCoordinator,
        ),
        ChangeNotifierProxyProvider<SettingsProvider, ReaderProvider>(
          create: (_) => ReaderProvider(
            application: bootstrap.container.contentReaderApplication,
          ),
          update: (_, settings, reader) => reader!..updateSettings(settings),
        ),
        ChangeNotifierProxyProvider<SettingsProvider, SearchProvider>(
          create: (_) => SearchProvider(
            contentSearchApplication:
                bootstrap.container.contentSearchApplication,
          ),
          update: (_, settings, search) => search!..updateSettings(settings),
        ),
      ],
      child: MaterialApp(
        title: 'Content Seeker',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorSchemeSeed: Colors.deepPurple,
          useMaterial3: true,
          brightness: Brightness.light,
        ),
        darkTheme: ThemeData(
          colorSchemeSeed: Colors.deepPurple,
          useMaterial3: true,
          brightness: Brightness.dark,
        ),
        themeMode: ThemeMode.system,
        home: const SearchPage(),
      ),
    );
  }
}
