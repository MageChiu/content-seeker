enum ContentSourceGroup { core, expansion, supplement }

enum SourceRegion { domestic, international }

enum SourceAccessMode { publicApi, officialApi, remoteOnly }

enum SourceStabilityTier { stable, experimental, fragile }

class ContentSourceDescriptor {
  final String key;
  final String label;
  final ContentSourceGroup group;
  final SourceRegion region;
  final SourceAccessMode accessMode;
  final SourceStabilityTier stabilityTier;
  final bool supportsLocalSearch;
  final bool supportsRemoteSearch;
  final bool requiresLocalApiKey;
  final bool enabledByDefault;
  final bool supportsVideo;
  final bool supportsAudio;
  final String localSearchDescription;
  final String remoteSearchDescription;
  /// 凭证字段提示，用于设置页动态展示输入框
  final List<CredentialHint> credentialHints;
  /// 是否支持用户自定义实例地址
  final bool supportsCustomBaseUrl;

  const ContentSourceDescriptor({
    required this.key,
    required this.label,
    required this.group,
    this.region = SourceRegion.international,
    this.accessMode = SourceAccessMode.publicApi,
    this.stabilityTier = SourceStabilityTier.stable,
    required this.supportsLocalSearch,
    required this.supportsRemoteSearch,
    required this.requiresLocalApiKey,
    required this.enabledByDefault,
    required this.supportsVideo,
    required this.supportsAudio,
    required this.localSearchDescription,
    required this.remoteSearchDescription,
    this.credentialHints = const [],
    this.supportsCustomBaseUrl = false,
  });
}

class CredentialHint {
  final String credKey;
  final String label;
  final String hint;
  final bool obscure;

  const CredentialHint({
    required this.credKey,
    required this.label,
    required this.hint,
    this.obscure = true,
  });
}

const Map<String, ContentSourceDescriptor> kContentSourceCatalog = {
  'youtube': ContentSourceDescriptor(
    key: 'youtube',
    label: 'YouTube',
    group: ContentSourceGroup.core,
    region: SourceRegion.international,
    accessMode: SourceAccessMode.officialApi,
    stabilityTier: SourceStabilityTier.stable,
    supportsLocalSearch: true,
    supportsRemoteSearch: true,
    requiresLocalApiKey: true,
    enabledByDefault: true,
    supportsVideo: true,
    supportsAudio: true,
    localSearchDescription: '本地搜索需要 YouTube Data API Key',
    remoteSearchDescription: '远程搜索由服务端统一聚合',
    credentialHints: [
      CredentialHint(credKey: 'apiKey', label: 'API Key', hint: '输入 YouTube Data API Key'),
    ],
  ),
  'bilibili': ContentSourceDescriptor(
    key: 'bilibili',
    label: 'Bilibili',
    group: ContentSourceGroup.core,
    region: SourceRegion.domestic,
    accessMode: SourceAccessMode.publicApi,
    stabilityTier: SourceStabilityTier.fragile,
    supportsLocalSearch: true,
    supportsRemoteSearch: true,
    requiresLocalApiKey: false,
    enabledByDefault: true,
    supportsVideo: true,
    supportsAudio: false,
    localSearchDescription:
        '本地搜索会自动进行匿名 cookie bootstrap + WBI 签名；可额外提供 Cookie/SESSDATA 提升稳定性',
    remoteSearchDescription: '远程搜索由服务端统一聚合',
    credentialHints: [
      CredentialHint(
        credKey: 'cookie',
        label: 'Cookie',
        hint: '可选：粘贴浏览器中的整段 Cookie',
        obscure: false,
      ),
      CredentialHint(
        credKey: 'sessdata',
        label: 'SESSDATA',
        hint: '可选：单独填写 SESSDATA',
      ),
      CredentialHint(
        credKey: 'buvid3',
        label: 'buvid3',
        hint: '可选：单独填写 buvid3',
        obscure: false,
      ),
      CredentialHint(
        credKey: 'buvid4',
        label: 'buvid4',
        hint: '可选：单独填写 buvid4',
        obscure: false,
      ),
    ],
  ),
  'dailymotion': ContentSourceDescriptor(
    key: 'dailymotion',
    label: 'Dailymotion',
    group: ContentSourceGroup.expansion,
    region: SourceRegion.international,
    accessMode: SourceAccessMode.officialApi,
    stabilityTier: SourceStabilityTier.stable,
    supportsLocalSearch: true,
    supportsRemoteSearch: false,
    requiresLocalApiKey: false,
    enabledByDefault: false,
    supportsVideo: true,
    supportsAudio: false,
    localSearchDescription: '客户端可直连 Dailymotion 公开视频搜索接口',
    remoteSearchDescription: '当前不支持远程搜索',
  ),
  'vimeo': ContentSourceDescriptor(
    key: 'vimeo',
    label: 'Vimeo',
    group: ContentSourceGroup.expansion,
    region: SourceRegion.international,
    accessMode: SourceAccessMode.officialApi,
    stabilityTier: SourceStabilityTier.stable,
    supportsLocalSearch: true,
    supportsRemoteSearch: false,
    requiresLocalApiKey: true,
    enabledByDefault: false,
    supportsVideo: true,
    supportsAudio: false,
    localSearchDescription: '客户端直连 Vimeo API 搜索视频，需要 Access Token',
    remoteSearchDescription: '当前不支持远程搜索',
    credentialHints: [
      CredentialHint(credKey: 'accessToken', label: 'Access Token', hint: '输入 Vimeo Personal Access Token'),
    ],
  ),
  'peertube': ContentSourceDescriptor(
    key: 'peertube',
    label: 'PeerTube',
    group: ContentSourceGroup.expansion,
    region: SourceRegion.international,
    accessMode: SourceAccessMode.publicApi,
    stabilityTier: SourceStabilityTier.experimental,
    supportsLocalSearch: true,
    supportsRemoteSearch: false,
    requiresLocalApiKey: false,
    enabledByDefault: false,
    supportsVideo: true,
    supportsAudio: false,
    localSearchDescription: '客户端可连接 PeerTube 公共实例搜索视频，支持自定义实例地址',
    remoteSearchDescription: '当前不支持远程搜索',
    supportsCustomBaseUrl: true,
  ),
  'acfun': ContentSourceDescriptor(
    key: 'acfun',
    label: 'AcFun',
    group: ContentSourceGroup.expansion,
    region: SourceRegion.domestic,
    accessMode: SourceAccessMode.publicApi,
    stabilityTier: SourceStabilityTier.experimental,
    supportsLocalSearch: true,
    supportsRemoteSearch: false,
    requiresLocalApiKey: false,
    enabledByDefault: false,
    supportsVideo: true,
    supportsAudio: false,
    localSearchDescription: '客户端可直连 AcFun 公开搜索接口',
    remoteSearchDescription: '当前不支持远程搜索',
  ),
  'youku': ContentSourceDescriptor(
    key: 'youku',
    label: '优酷',
    group: ContentSourceGroup.expansion,
    region: SourceRegion.domestic,
    accessMode: SourceAccessMode.officialApi,
    stabilityTier: SourceStabilityTier.experimental,
    supportsLocalSearch: true,
    supportsRemoteSearch: false,
    requiresLocalApiKey: true,
    enabledByDefault: false,
    supportsVideo: true,
    supportsAudio: false,
    localSearchDescription: '客户端直连优酷开放平台搜索视频，需要 Client ID',
    remoteSearchDescription: '当前不支持远程搜索',
    credentialHints: [
      CredentialHint(credKey: 'clientId', label: 'Client ID', hint: '输入优酷开放平台 Client ID'),
    ],
  ),
  'itunes': ContentSourceDescriptor(
    key: 'itunes',
    label: 'Apple Music Preview',
    group: ContentSourceGroup.core,
    region: SourceRegion.international,
    accessMode: SourceAccessMode.publicApi,
    stabilityTier: SourceStabilityTier.stable,
    supportsLocalSearch: true,
    supportsRemoteSearch: false,
    requiresLocalApiKey: false,
    enabledByDefault: true,
    supportsVideo: false,
    supportsAudio: true,
    localSearchDescription: '客户端直连 iTunes Search API，返回 30 秒预览音频',
    remoteSearchDescription: '当前不支持远程搜索',
  ),
  'deezer': ContentSourceDescriptor(
    key: 'deezer',
    label: 'Deezer',
    group: ContentSourceGroup.expansion,
    region: SourceRegion.international,
    accessMode: SourceAccessMode.publicApi,
    stabilityTier: SourceStabilityTier.stable,
    supportsLocalSearch: true,
    supportsRemoteSearch: false,
    requiresLocalApiKey: false,
    enabledByDefault: false,
    supportsVideo: false,
    supportsAudio: true,
    localSearchDescription: '客户端可直连 Deezer 搜索接口并返回官方预览音频',
    remoteSearchDescription: '当前不支持远程搜索',
  ),
  'internet_archive': ContentSourceDescriptor(
    key: 'internet_archive',
    label: 'Internet Archive Audio',
    group: ContentSourceGroup.expansion,
    region: SourceRegion.international,
    accessMode: SourceAccessMode.publicApi,
    stabilityTier: SourceStabilityTier.stable,
    supportsLocalSearch: true,
    supportsRemoteSearch: false,
    requiresLocalApiKey: false,
    enabledByDefault: false,
    supportsVideo: false,
    supportsAudio: true,
    localSearchDescription: '客户端可查询 Internet Archive 音频馆藏并尝试直连音频文件',
    remoteSearchDescription: '当前不支持远程搜索',
  ),
  'internet_archive_video': ContentSourceDescriptor(
    key: 'internet_archive_video',
    label: 'Internet Archive Video',
    group: ContentSourceGroup.expansion,
    region: SourceRegion.international,
    accessMode: SourceAccessMode.publicApi,
    stabilityTier: SourceStabilityTier.stable,
    supportsLocalSearch: true,
    supportsRemoteSearch: false,
    requiresLocalApiKey: false,
    enabledByDefault: false,
    supportsVideo: true,
    supportsAudio: false,
    localSearchDescription: '客户端可查询 Internet Archive 视频馆藏并打开嵌入播放页',
    remoteSearchDescription: '当前不支持远程搜索',
  ),
  'jamendo': ContentSourceDescriptor(
    key: 'jamendo',
    label: 'Jamendo',
    group: ContentSourceGroup.core,
    region: SourceRegion.international,
    accessMode: SourceAccessMode.officialApi,
    stabilityTier: SourceStabilityTier.stable,
    supportsLocalSearch: true,
    supportsRemoteSearch: false,
    requiresLocalApiKey: true,
    enabledByDefault: true,
    supportsVideo: false,
    supportsAudio: true,
    localSearchDescription: '客户端直连 Jamendo API，需要 Jamendo Client ID',
    remoteSearchDescription: '当前不支持远程搜索',
    credentialHints: [
      CredentialHint(credKey: 'apiKey', label: 'Client ID', hint: '输入 Jamendo Client ID'),
    ],
  ),
};

ContentSourceDescriptor sourceDescriptor(String source) {
  final normalized = source.trim().toLowerCase();
  return kContentSourceCatalog[normalized] ??
      ContentSourceDescriptor(
        key: normalized,
        label: normalized.isEmpty ? 'Unknown Source' : normalized,
        group: ContentSourceGroup.expansion,
        supportsLocalSearch: false,
        supportsRemoteSearch: false,
        requiresLocalApiKey: false,
        enabledByDefault: false,
        supportsVideo: false,
        supportsAudio: false,
        localSearchDescription: '当前不支持客户端本地搜索',
        remoteSearchDescription: '当前不支持远程搜索',
      );
}
