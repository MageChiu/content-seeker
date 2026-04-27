import 'dependency_container.dart';
import '../../features/settings/settings_provider.dart';

class AppBootstrap {
  final DependencyContainer container;

  const AppBootstrap({required this.container});

  factory AppBootstrap.create({SettingsProvider? settingsProvider}) {
    return AppBootstrap(
      container: DependencyContainer.bootstrap(settingsProvider: settingsProvider),
    );
  }
}
