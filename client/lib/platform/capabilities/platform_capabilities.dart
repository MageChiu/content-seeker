class PlatformCapabilities {
  final bool isDesktop;
  final bool isMobile;
  final bool isWeb;
  final bool supportsBackgroundDownload;
  final bool supportsDesktopLocalToolchain;
  final bool supportsProgressiveCachePlayback;
  final bool supportsTorrent;

  const PlatformCapabilities({
    required this.isDesktop,
    required this.isMobile,
    required this.isWeb,
    required this.supportsBackgroundDownload,
    required this.supportsDesktopLocalToolchain,
    required this.supportsProgressiveCachePlayback,
    required this.supportsTorrent,
  });

  static const unsupported = PlatformCapabilities(
    isDesktop: false,
    isMobile: false,
    isWeb: false,
    supportsBackgroundDownload: false,
    supportsDesktopLocalToolchain: false,
    supportsProgressiveCachePlayback: false,
    supportsTorrent: false,
  );
}
