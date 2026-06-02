import '../feature_flags/feature_policy.dart';
import '../feature_flags/app_feature.dart';

class AppEnvironment {
  final FeaturePolicy featurePolicy;

  const AppEnvironment({required this.featurePolicy});

  factory AppEnvironment.defaultEnvironment() {
    return const AppEnvironment(
      featurePolicy: FeaturePolicy(
        enabledFeatures: {
          AppFeature.stablePlayback,
        },
        visibleFeatures: {
          AppFeature.stablePlayback,
          AppFeature.basicDownload,
          AppFeature.offlineLibrary,
        },
      ),
    );
  }
}
