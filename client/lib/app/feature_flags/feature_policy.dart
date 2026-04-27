import 'app_feature.dart';

class FeaturePolicy {
  final Set<AppFeature> enabledFeatures;
  final Set<AppFeature> visibleFeatures;

  const FeaturePolicy({
    this.enabledFeatures = const <AppFeature>{},
    this.visibleFeatures = const <AppFeature>{},
  });

  bool isEnabled(AppFeature feature) => enabledFeatures.contains(feature);

  bool isVisible(AppFeature feature) => visibleFeatures.contains(feature);

  FeaturePolicy copyWith({
    Set<AppFeature>? enabledFeatures,
    Set<AppFeature>? visibleFeatures,
  }) {
    return FeaturePolicy(
      enabledFeatures: enabledFeatures ?? this.enabledFeatures,
      visibleFeatures: visibleFeatures ?? this.visibleFeatures,
    );
  }
}
