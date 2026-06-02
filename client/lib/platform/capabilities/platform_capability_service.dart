import 'platform_capabilities.dart';
import 'platform_capability_service_stub.dart'
    if (dart.library.io) 'platform_capability_service_io.dart';

abstract class PlatformCapabilityService {
  PlatformCapabilities current();
}

PlatformCapabilityService createPlatformCapabilityService() =>
    createPlatformCapabilityServiceImpl();
