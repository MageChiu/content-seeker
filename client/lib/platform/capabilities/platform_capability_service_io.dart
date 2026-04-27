import 'dart:io';

import 'platform_capabilities.dart';
import 'platform_capability_service.dart';

class _IoPlatformCapabilityService implements PlatformCapabilityService {
  @override
  PlatformCapabilities current() {
    final isDesktop =
        Platform.isMacOS || Platform.isWindows || Platform.isLinux;
    final isMobile = Platform.isIOS || Platform.isAndroid;

    return PlatformCapabilities(
      isDesktop: isDesktop,
      isMobile: isMobile,
      isWeb: false,
      supportsBackgroundDownload: isMobile,
      supportsDesktopLocalToolchain: isDesktop,
      supportsProgressiveCachePlayback: isDesktop,
      supportsTorrent: isDesktop,
    );
  }
}

PlatformCapabilityService createPlatformCapabilityServiceImpl() =>
    _IoPlatformCapabilityService();
