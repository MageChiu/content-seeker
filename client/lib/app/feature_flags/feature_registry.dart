import '../../platform/capabilities/platform_capabilities.dart';
import 'app_feature.dart';
import 'feature_gate.dart';
import 'feature_policy.dart';

class FeatureRegistry implements FeatureGate {
  final PlatformCapabilities capabilities;
  final FeaturePolicy policy;

  const FeatureRegistry({
    required this.capabilities,
    required this.policy,
  });

  @override
  bool isEnabled(AppFeature feature) {
    if (!_isSupportedOnCurrentPlatform(feature)) {
      return false;
    }
    return policy.isEnabled(feature);
  }

  @override
  bool isVisible(AppFeature feature) {
    if (!_isSupportedOnCurrentPlatform(feature)) {
      return false;
    }
    return policy.isVisible(feature);
  }

  bool _isSupportedOnCurrentPlatform(AppFeature feature) {
    switch (feature) {
      case AppFeature.stablePlayback:
      case AppFeature.basicDownload:
      case AppFeature.offlineLibrary:
      case AppFeature.externalSubtitleSupport:
        return true;
      case AppFeature.progressiveCachePlayback:
        return capabilities.supportsProgressiveCachePlayback;
      case AppFeature.desktopEnhancedResolver:
      case AppFeature.desktopLocalToolchain:
        return capabilities.supportsDesktopLocalToolchain;
      case AppFeature.desktopTorrent:
        return capabilities.supportsTorrent;
      case AppFeature.mobileBackgroundDownload:
        return capabilities.supportsBackgroundDownload;
    }
  }
}
