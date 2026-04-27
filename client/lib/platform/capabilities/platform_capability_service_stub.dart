import 'platform_capabilities.dart';
import 'platform_capability_service.dart';

class _UnsupportedPlatformCapabilityService
    implements PlatformCapabilityService {
  @override
  PlatformCapabilities current() => PlatformCapabilities.unsupported;
}

PlatformCapabilityService createPlatformCapabilityServiceImpl() =>
    _UnsupportedPlatformCapabilityService();
