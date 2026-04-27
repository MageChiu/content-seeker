import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'features/search/search_provider.dart';
import 'features/settings/settings_provider.dart';
import 'features/search/search_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const ContentSeekerApp());
}

class ContentSeekerApp extends StatelessWidget {
  const ContentSeekerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProxyProvider<SettingsProvider, SearchProvider>(
          create: (_) => SearchProvider(),
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
