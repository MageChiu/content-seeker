class SourceCapability {
  final bool supportsDownload;
  final bool supportsOffline;
  final bool supportsProgressiveCache;
  final bool requiresAuthentication;

  const SourceCapability({
    this.supportsDownload = false,
    this.supportsOffline = false,
    this.supportsProgressiveCache = false,
    this.requiresAuthentication = false,
  });
}
