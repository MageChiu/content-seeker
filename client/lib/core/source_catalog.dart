class ContentSourceDescriptor {
  final String key;
  final String label;
  final bool supportsLocalSearch;
  final bool supportsRemoteSearch;
  final bool requiresLocalApiKey;
  final String localSearchDescription;
  final String remoteSearchDescription;

  const ContentSourceDescriptor({
    required this.key,
    required this.label,
    required this.supportsLocalSearch,
    required this.supportsRemoteSearch,
    required this.requiresLocalApiKey,
    required this.localSearchDescription,
    required this.remoteSearchDescription,
  });
}

const Map<String, ContentSourceDescriptor> kContentSourceCatalog = {
  'youtube': ContentSourceDescriptor(
    key: 'youtube',
    label: 'YouTube',
    supportsLocalSearch: true,
    supportsRemoteSearch: true,
    requiresLocalApiKey: true,
    localSearchDescription: '本地搜索需要 YouTube Data API Key',
    remoteSearchDescription: '远程搜索由服务端统一聚合',
  ),
  'bilibili': ContentSourceDescriptor(
    key: 'bilibili',
    label: 'Bilibili',
    supportsLocalSearch: true,
    supportsRemoteSearch: true,
    requiresLocalApiKey: false,
    localSearchDescription: '本地搜索可直接使用公开接口',
    remoteSearchDescription: '远程搜索由服务端统一聚合',
  ),
  'itunes': ContentSourceDescriptor(
    key: 'itunes',
    label: 'Apple Music Preview',
    supportsLocalSearch: true,
    supportsRemoteSearch: true,
    requiresLocalApiKey: false,
    localSearchDescription: '客户端直连 iTunes Search API，返回 30 秒预览音频',
    remoteSearchDescription: '远程搜索可返回 Apple Music 30 秒预览音频',
  ),
  'jamendo': ContentSourceDescriptor(
    key: 'jamendo',
    label: 'Jamendo',
    supportsLocalSearch: true,
    supportsRemoteSearch: true,
    requiresLocalApiKey: true,
    localSearchDescription: '客户端直连 Jamendo API，需要 Jamendo Client ID',
    remoteSearchDescription: '远程搜索可返回 Jamendo 官方音乐结果',
  ),
  'podcast': ContentSourceDescriptor(
    key: 'podcast',
    label: 'Podcast',
    supportsLocalSearch: false,
    supportsRemoteSearch: true,
    requiresLocalApiKey: false,
    localSearchDescription: '当前不支持客户端本地搜索',
    remoteSearchDescription: '远程搜索返回播客节目与单集索引结果',
  ),
  'google': ContentSourceDescriptor(
    key: 'google',
    label: 'Google Supplement',
    supportsLocalSearch: false,
    supportsRemoteSearch: true,
    requiresLocalApiKey: false,
    localSearchDescription: '当前不支持客户端本地搜索',
    remoteSearchDescription: '远程搜索用于补充网页媒体索引结果',
  ),
};

ContentSourceDescriptor sourceDescriptor(String source) {
  final normalized = source.trim().toLowerCase();
  return kContentSourceCatalog[normalized] ??
      ContentSourceDescriptor(
        key: normalized,
        label: normalized.isEmpty ? 'Unknown Source' : normalized,
        supportsLocalSearch: false,
        supportsRemoteSearch: true,
        requiresLocalApiKey: false,
        localSearchDescription: '当前不支持客户端本地搜索',
        remoteSearchDescription: '远程搜索能力由服务端决定',
      );
}
