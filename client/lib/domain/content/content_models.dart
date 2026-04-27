enum ContentType {
  video,
  audio,
  article,
  webArticle,
  rss,
  novel,
  comic,
  subtitle,
  image,
  playlist,
  collection,
  creator,
  channel,
  unknown,
}

enum ContentReaderKind {
  webArticle,
  rss,
  novel,
  comic,
  subtitle,
  unknown,
}

enum ContentCapability {
  search,
  detail,
  open,
  download,
  save,
  library,
  subscribe,
}

enum ContentEntityKind {
  item,
  collection,
  creator,
}

enum ContentOpenMode {
  inAppPlayer,
  webView,
  externalBrowser,
  externalApp,
}

enum ContentSaveMode {
  favorite,
  bookmark,
  archive,
  history,
}

enum ContentSubscriptionState {
  active,
  paused,
  cancelled,
}

class ContentSourceRef {
  final String sourceId;
  final String adapterId;
  final String displayName;
  final Set<ContentCapability> capabilities;

  const ContentSourceRef({
    required this.sourceId,
    this.adapterId = '',
    this.displayName = '',
    this.capabilities = const {},
  });

  bool supports(ContentCapability capability) {
    return capabilities.contains(capability);
  }
}

class ContentHandle {
  final String id;
  final String canonicalId;
  final ContentType type;
  final ContentEntityKind kind;
  final ContentSourceRef source;

  const ContentHandle({
    required this.id,
    required this.type,
    required this.source,
    this.canonicalId = '',
    this.kind = ContentEntityKind.item,
  });

  String get stableId => canonicalId.isNotEmpty ? canonicalId : id;
}

class ContentEntity {
  final ContentHandle handle;
  final String title;
  final String subtitle;
  final String summary;
  final ContentReaderKind readerKind;
  final Uri? coverUri;
  final Uri? canonicalUri;
  final Duration? duration;
  final DateTime? publishedAt;
  final Set<ContentCapability> capabilities;
  final Map<String, Object?> metadata;
  final List<String> tags;

  const ContentEntity({
    required this.handle,
    required this.title,
    this.subtitle = '',
    this.summary = '',
    this.readerKind = ContentReaderKind.unknown,
    this.coverUri,
    this.canonicalUri,
    this.duration,
    this.publishedAt,
    this.capabilities = const {},
    this.metadata = const {},
    this.tags = const [],
  });

  bool supports(ContentCapability capability) {
    return capabilities.contains(capability) || handle.source.supports(capability);
  }
}

class ContentDetail {
  final ContentEntity entity;
  final String description;
  final List<ContentEntity> related;
  final Map<String, Object?> sections;

  const ContentDetail({
    required this.entity,
    this.description = '',
    this.related = const [],
    this.sections = const {},
  });
}

class CursorPage<T> {
  final List<T> items;
  final String nextCursor;
  final bool hasMore;

  const CursorPage({
    required this.items,
    this.nextCursor = '',
    this.hasMore = false,
  });
}

class ContentSearchRequest {
  final String query;
  final Set<ContentType> types;
  final Set<String> sourceIds;
  final String cursor;
  final int limit;
  final Map<String, Object?> filters;

  const ContentSearchRequest({
    required this.query,
    this.types = const {},
    this.sourceIds = const {},
    this.cursor = '',
    this.limit = 20,
    this.filters = const {},
  });
}

class ContentSearchResult {
  final ContentEntity entity;
  final double score;
  final List<String> highlights;

  const ContentSearchResult({
    required this.entity,
    this.score = 0,
    this.highlights = const [],
  });
}

class ContentDetailRequest {
  final ContentHandle handle;
  final bool includeRelated;
  final bool includeSections;

  const ContentDetailRequest({
    required this.handle,
    this.includeRelated = true,
    this.includeSections = true,
  });
}

class ContentOpenRequest {
  final ContentHandle handle;
  final ContentOpenMode preferredMode;
  final Map<String, Object?> context;

  const ContentOpenRequest({
    required this.handle,
    this.preferredMode = ContentOpenMode.inAppPlayer,
    this.context = const {},
  });
}

class ContentOpenTarget {
  final ContentHandle handle;
  final ContentOpenMode mode;
  final Uri target;
  final Map<String, String> headers;
  final Map<String, Object?> extras;

  const ContentOpenTarget({
    required this.handle,
    required this.mode,
    required this.target,
    this.headers = const {},
    this.extras = const {},
  });
}

class ContentDownloadRequest {
  final ContentHandle handle;
  final String filename;
  final Uri? preferredUri;
  final Map<String, String> headers;
  final Map<String, Object?> options;

  const ContentDownloadRequest({
    required this.handle,
    this.filename = '',
    this.preferredUri,
    this.headers = const {},
    this.options = const {},
  });
}

class ContentDownloadPlan {
  final ContentHandle handle;
  final Uri uri;
  final String filename;
  final String mimeType;
  final Map<String, String> headers;

  const ContentDownloadPlan({
    required this.handle,
    required this.uri,
    required this.filename,
    this.mimeType = '',
    this.headers = const {},
  });
}

class ContentSaveRequest {
  final ContentEntity entity;
  final ContentSaveMode mode;
  final Map<String, Object?> payload;

  const ContentSaveRequest({
    required this.entity,
    this.mode = ContentSaveMode.favorite,
    this.payload = const {},
  });
}

class ContentSaveReceipt {
  final String recordId;
  final ContentEntity entity;
  final ContentSaveMode mode;
  final DateTime savedAt;
  final String snapshotPath;
  final String offlineAssetId;

  const ContentSaveReceipt({
    required this.recordId,
    required this.entity,
    required this.mode,
    required this.savedAt,
    this.snapshotPath = '',
    this.offlineAssetId = '',
  });
}

class ContentLibraryQuery {
  final Set<ContentSaveMode> modes;
  final Set<ContentType> types;
  final String cursor;
  final int limit;

  const ContentLibraryQuery({
    this.modes = const {},
    this.types = const {},
    this.cursor = '',
    this.limit = 20,
  });
}

class ContentLibraryEntry {
  final String entryId;
  final ContentEntity entity;
  final ContentSaveMode mode;
  final DateTime createdAt;
  final String snapshotPath;
  final String offlineAssetId;

  const ContentLibraryEntry({
    required this.entryId,
    required this.entity,
    required this.mode,
    required this.createdAt,
    this.snapshotPath = '',
    this.offlineAssetId = '',
  });
}

class ContentSubscriptionRequest {
  final ContentHandle handle;
  final ContentEntity? entity;
  final Map<String, Object?> options;

  const ContentSubscriptionRequest({
    required this.handle,
    this.entity,
    this.options = const {},
  });
}

class ContentSubscriptionQuery {
  final Set<ContentSubscriptionState> states;
  final Set<ContentType> types;
  final Set<String> sourceIds;
  final String cursor;
  final int limit;

  const ContentSubscriptionQuery({
    this.states = const {},
    this.types = const {},
    this.sourceIds = const {},
    this.cursor = '',
    this.limit = 20,
  });
}

class ContentSubscriptionRecord {
  final String subscriptionId;
  final ContentHandle handle;
  final ContentEntity? entity;
  final ContentSubscriptionState state;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const ContentSubscriptionRecord({
    required this.subscriptionId,
    required this.handle,
    this.entity,
    required this.state,
    required this.createdAt,
    this.updatedAt,
  });
}
