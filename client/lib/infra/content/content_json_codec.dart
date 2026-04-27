import '../../core/content/content.dart';

Map<String, Object?> encodeContentHandle(ContentHandle handle) {
  return {
    'id': handle.id,
    'canonical_id': handle.canonicalId,
    'type': handle.type.name,
    'kind': handle.kind.name,
    'source': encodeContentSourceRef(handle.source),
  };
}

ContentHandle decodeContentHandle(Map<String, dynamic> json) {
  return ContentHandle(
    id: '${json['id'] ?? ''}',
    canonicalId: '${json['canonical_id'] ?? ''}',
    type: _parseContentType(json['type']),
    kind: _parseEntityKind(json['kind']),
    source: decodeContentSourceRef(
      Map<String, dynamic>.from(json['source'] as Map? ?? const {}),
    ),
  );
}

Map<String, Object?> encodeContentSourceRef(ContentSourceRef source) {
  return {
    'source_id': source.sourceId,
    'adapter_id': source.adapterId,
    'display_name': source.displayName,
    'capabilities': source.capabilities.map((item) => item.name).toList(),
  };
}

ContentSourceRef decodeContentSourceRef(Map<String, dynamic> json) {
  return ContentSourceRef(
    sourceId: '${json['source_id'] ?? ''}',
    adapterId: '${json['adapter_id'] ?? ''}',
    displayName: '${json['display_name'] ?? ''}',
    capabilities: _parseCapabilities(json['capabilities']),
  );
}

Map<String, Object?> encodeContentEntity(ContentEntity entity) {
  return {
    'handle': encodeContentHandle(entity.handle),
    'title': entity.title,
    'subtitle': entity.subtitle,
    'summary': entity.summary,
    'reader_kind': entity.readerKind.name,
    'cover_uri': entity.coverUri?.toString(),
    'canonical_uri': entity.canonicalUri?.toString(),
    'duration_ms': entity.duration?.inMilliseconds,
    'published_at': entity.publishedAt?.toIso8601String(),
    'capabilities': entity.capabilities.map((item) => item.name).toList(),
    'metadata': _toJsonValue(entity.metadata),
    'tags': entity.tags,
  };
}

ContentEntity decodeContentEntity(Map<String, dynamic> json) {
  return ContentEntity(
    handle: decodeContentHandle(
      Map<String, dynamic>.from(json['handle'] as Map? ?? const {}),
    ),
    title: '${json['title'] ?? ''}',
    subtitle: '${json['subtitle'] ?? ''}',
    summary: '${json['summary'] ?? ''}',
    readerKind: _parseReaderKind(json['reader_kind']),
    coverUri: _parseUri(json['cover_uri']),
    canonicalUri: _parseUri(json['canonical_uri']),
    duration: _readInt(json['duration_ms']) > 0
        ? Duration(milliseconds: _readInt(json['duration_ms']))
        : null,
    publishedAt: DateTime.tryParse('${json['published_at'] ?? ''}'),
    capabilities: _parseCapabilities(json['capabilities']),
    metadata: _decodeJsonMap(json['metadata']),
    tags: (json['tags'] as List? ?? const [])
        .map((item) => '$item')
        .toList(growable: false),
  );
}

Map<String, Object?> encodeContentDetail(ContentDetail detail) {
  return {
    'entity': encodeContentEntity(detail.entity),
    'description': detail.description,
    'related': detail.related.map(encodeContentEntity).toList(growable: false),
    'sections': _toJsonValue(detail.sections),
  };
}

ContentDetail decodeContentDetail(Map<String, dynamic> json) {
  return ContentDetail(
    entity: decodeContentEntity(
      Map<String, dynamic>.from(json['entity'] as Map? ?? const {}),
    ),
    description: '${json['description'] ?? ''}',
    related: (json['related'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => decodeContentEntity(Map<String, dynamic>.from(item)))
        .toList(growable: false),
    sections: _decodeJsonMap(json['sections']),
  );
}

Map<String, Object?> encodeLibraryEntry(ContentLibraryEntry entry) {
  return {
    'entry_id': entry.entryId,
    'entity': encodeContentEntity(entry.entity),
    'mode': entry.mode.name,
    'created_at': entry.createdAt.toIso8601String(),
    'snapshot_path': entry.snapshotPath,
    'offline_asset_id': entry.offlineAssetId,
  };
}

ContentLibraryEntry decodeLibraryEntry(Map<String, dynamic> json) {
  return ContentLibraryEntry(
    entryId: '${json['entry_id'] ?? ''}',
    entity: decodeContentEntity(
      Map<String, dynamic>.from(json['entity'] as Map? ?? const {}),
    ),
    mode: _parseSaveMode(json['mode']),
    createdAt: DateTime.tryParse('${json['created_at'] ?? ''}') ??
        DateTime.fromMillisecondsSinceEpoch(0),
    snapshotPath: '${json['snapshot_path'] ?? ''}',
    offlineAssetId: '${json['offline_asset_id'] ?? ''}',
  );
}

Map<String, Object?> encodeSubscriptionRecord(ContentSubscriptionRecord record) {
  return {
    'subscription_id': record.subscriptionId,
    'handle': encodeContentHandle(record.handle),
    'entity': record.entity == null ? null : encodeContentEntity(record.entity!),
    'state': record.state.name,
    'created_at': record.createdAt.toIso8601String(),
    'updated_at': record.updatedAt?.toIso8601String(),
  };
}

ContentSubscriptionRecord decodeSubscriptionRecord(Map<String, dynamic> json) {
  return ContentSubscriptionRecord(
    subscriptionId: '${json['subscription_id'] ?? ''}',
    handle: decodeContentHandle(
      Map<String, dynamic>.from(json['handle'] as Map? ?? const {}),
    ),
    entity: json['entity'] is Map
        ? decodeContentEntity(Map<String, dynamic>.from(json['entity'] as Map))
        : null,
    state: _parseSubscriptionState(json['state']),
    createdAt: DateTime.tryParse('${json['created_at'] ?? ''}') ??
        DateTime.fromMillisecondsSinceEpoch(0),
    updatedAt: DateTime.tryParse('${json['updated_at'] ?? ''}'),
  );
}

Object? _toJsonValue(Object? value) {
  if (value == null ||
      value is num ||
      value is String ||
      value is bool) {
    return value;
  }
  if (value is DateTime) {
    return value.toIso8601String();
  }
  if (value is Uri) {
    return value.toString();
  }
  if (value is List) {
    return value.map(_toJsonValue).toList(growable: false);
  }
  if (value is Map) {
    return value.map(
      (key, item) => MapEntry('$key', _toJsonValue(item)),
    );
  }
  return '$value';
}

Map<String, Object?> _decodeJsonMap(Object? value) {
  if (value is! Map) {
    return const {};
  }
  return value.map((key, item) => MapEntry('$key', item));
}

Set<ContentCapability> _parseCapabilities(Object? value) {
  if (value is! List) {
    return const {};
  }
  return value.map((item) => _parseCapability(item)).toSet();
}

ContentCapability _parseCapability(Object? value) {
  switch ('$value'.trim().toLowerCase()) {
    case 'detail':
      return ContentCapability.detail;
    case 'open':
      return ContentCapability.open;
    case 'download':
      return ContentCapability.download;
    case 'save':
      return ContentCapability.save;
    case 'library':
      return ContentCapability.library;
    case 'subscribe':
      return ContentCapability.subscribe;
    default:
      return ContentCapability.search;
  }
}

ContentType _parseContentType(Object? value) {
  switch ('$value'.trim()) {
    case 'audio':
      return ContentType.audio;
    case 'article':
      return ContentType.article;
    case 'webArticle':
      return ContentType.webArticle;
    case 'rss':
      return ContentType.rss;
    case 'novel':
      return ContentType.novel;
    case 'comic':
      return ContentType.comic;
    case 'subtitle':
      return ContentType.subtitle;
    case 'image':
      return ContentType.image;
    case 'playlist':
      return ContentType.playlist;
    case 'collection':
      return ContentType.collection;
    case 'creator':
      return ContentType.creator;
    case 'channel':
      return ContentType.channel;
    case 'video':
      return ContentType.video;
    default:
      return ContentType.unknown;
  }
}

ContentEntityKind _parseEntityKind(Object? value) {
  switch ('$value'.trim()) {
    case 'collection':
      return ContentEntityKind.collection;
    case 'creator':
      return ContentEntityKind.creator;
    default:
      return ContentEntityKind.item;
  }
}

ContentReaderKind _parseReaderKind(Object? value) {
  switch ('$value'.trim()) {
    case 'webArticle':
      return ContentReaderKind.webArticle;
    case 'rss':
      return ContentReaderKind.rss;
    case 'novel':
      return ContentReaderKind.novel;
    case 'comic':
      return ContentReaderKind.comic;
    case 'subtitle':
      return ContentReaderKind.subtitle;
    default:
      return ContentReaderKind.unknown;
  }
}

ContentSaveMode _parseSaveMode(Object? value) {
  switch ('$value'.trim()) {
    case 'bookmark':
      return ContentSaveMode.bookmark;
    case 'archive':
      return ContentSaveMode.archive;
    case 'history':
      return ContentSaveMode.history;
    default:
      return ContentSaveMode.favorite;
  }
}

ContentSubscriptionState _parseSubscriptionState(Object? value) {
  switch ('$value'.trim()) {
    case 'paused':
      return ContentSubscriptionState.paused;
    case 'cancelled':
    case 'canceled':
      return ContentSubscriptionState.cancelled;
    default:
      return ContentSubscriptionState.active;
  }
}

Uri? _parseUri(Object? value) {
  final raw = '$value'.trim();
  if (raw.isEmpty || raw == 'null') {
    return null;
  }
  return Uri.tryParse(raw);
}

int _readInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  return int.tryParse('$value') ?? 0;
}
