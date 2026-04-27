import 'app_feature.dart';

abstract class FeatureGate {
  bool isEnabled(AppFeature feature);
  bool isVisible(AppFeature feature);
}
