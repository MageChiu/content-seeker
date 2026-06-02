import '../../core/content/content_ports.dart';
import '../../core/search_source.dart';
import '../../domain/content/content_models.dart';
import '../../features/search/sources/server_source.dart';
import '../../models/search_result.dart';

const _legacyPlayUrlKey = 'legacy.playUrl';
const _legacyPlaybackKindKey = 'legacy.playbackKind';
const _legacyAvailabilityKey = 'legacy.availability';
const _legacySourceTierKey = 'legacy.sourceTier';
const _legacyArtistKey = 'legacy.artistOrAuthor';
const _legacyAlbumKey = 'legacy.albumOrSeries';
const _legacyDescriptionKey = 'legacy.description';
const _legacyAiSummaryKey = 'legacy.aiSummary';
const _legacyMediaTypeKey = 'legacy.mediaType';
const _legacyMediaSubtypeKey = 'legacy.mediaSubtype';
const _legacyThumbnailUrlKey = 'legacy.thumbnailUrl';
const _legacyCanonicalUrlKey = 'legacy.canonicalUrl';
const _legacyDurationSecondsKey = 'legacy.durationSeconds';
const _legacyHighlightsKey = 'legacy.highlights';

extension SearchResultContentSearchBridge on SearchResult {
  ContentSearchResult toContentSearchResult({
    String adapterId = '',
    double score = 0,
  }) {
    return ContentSearchResult(
      entity: ContentEntity(
        handle: ContentHandle(
          id: id,
          canonicalId: canonicalUrl.trim().isNotEmpty ? canonicalUrl.trim() : id,
          type: mediaType == MediaType.audio ? ContentType.audio : ContentType.video,
          source: ContentSourceRef(
            sourceId: sourceKey,
            adapterId: adapterId,
            displayName: sourceLabel,
            capabilities: {
              ContentCapability.search,
              if (isPlayable || hasPlayUrl) ContentCapability.open,
            },
          ),
        ),
        title: title,
        subtitle: metaLine ?? sourceLabel,
        summary: summaryText ?? '',
        coverUri: _parseUri(thumbnailUrl),
        canonicalUri: _parseUri(canonicalUrl),
        duration: durationSeconds > 0 ? Duration(seconds: durationSeconds) : null,
        capabilities: {
          ContentCapability.search,
          if (isPlayable || hasPlayUrl) ContentCapability.open,
        },
        metadata: {
          _legacyPlayUrlKey: playUrl,
          _legacyPlaybackKindKey: playbackKind.name,
          _legacyAvailabilityKey: availability.name,
          _legacySourceTierKey: sourceTier.name,
          _legacyArtistKey: artistOrAuthor,
          _legacyAlbumKey: albumOrSeries,
          _legacyDescriptionKey: description,
          _legacyAiSummaryKey: aiSummary,
          _legacyMediaTypeKey: mediaType.name,
          _legacyMediaSubtypeKey: mediaSubtype.name,
          _legacyThumbnailUrlKey: thumbnailUrl,
          _legacyCanonicalUrlKey: canonicalUrl,
          _legacyDurationSecondsKey: durationSeconds,
          _legacyHighlightsKey: highlights
              .map(
                (item) => <String, Object?>{
                  'timestamp_seconds': item.timestampSeconds,
                  'text': item.text,
                },
              )
              .toList(growable: false),
        },
      ),
      score: score,
      highlights: highlights
          .map((item) => item.text.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false),
    );
  }
}

extension ContentSearchResultLegacySearchBridge on ContentSearchResult {
  SearchResult toLegacySearchResult() {
    final entity = this.entity;
    final metadata = entity.metadata;
    final sourceId = entity.handle.source.sourceId.trim().toLowerCase();
    final canonicalUri = entity.canonicalUri;
    final duration =
        entity.duration?.inSeconds ?? _readInt(metadata[_legacyDurationSecondsKey]);

    return SearchResult(
      id: entity.handle.id,
      title: entity.title,
      source: sourceId,
      mediaType: _parseLegacyMediaType(
        metadata[_legacyMediaTypeKey],
        fallback: entity.handle.type,
      ),
      mediaSubtype: _parseLegacyMediaSubtype(
        metadata[_legacyMediaSubtypeKey],
        fallback: entity.handle.type,
      ),
      thumbnailUrl: _readString(
        metadata[_legacyThumbnailUrlKey],
        fallback: entity.coverUri?.toString() ?? '',
      ),
      durationSeconds: duration > 0 ? duration : 0,
      playUrl: _readString(
        metadata[_legacyPlayUrlKey],
        fallback: canonicalUri?.toString() ?? '',
      ),
      playbackKind: _parsePlaybackKind(metadata[_legacyPlaybackKindKey]),
      isPlayable: entity.supports(ContentCapability.open),
      availability: _parseAvailability(metadata[_legacyAvailabilityKey]),
      sourceTier: _parseSourceTier(metadata[_legacySourceTierKey]),
      canonicalUrl: _readString(
        metadata[_legacyCanonicalUrlKey],
        fallback: canonicalUri?.toString() ?? '',
      ),
      artistOrAuthor: _readString(
        metadata[_legacyArtistKey],
        fallback: _readString(entity.metadata['author']),
      ),
      albumOrSeries: _readString(
        metadata[_legacyAlbumKey],
        fallback: entity.subtitle,
      ),
      description: _readString(
        metadata[_legacyDescriptionKey],
        fallback: entity.summary,
      ),
      highlights: _parseHighlights(metadata[_legacyHighlightsKey]),
      aiSummary: _readNullableString(metadata[_legacyAiSummaryKey]),
      resultKind: _isReadingType(entity.handle.type)
          ? SearchResultKind.reading
          : SearchResultKind.media,
      openMode: _isReadingType(entity.handle.type)
          ? SearchResultOpenMode.reader
          : SearchResultOpenMode.player,
      contentTypeKey: entity.handle.type.name,
      readerKindKey: entity.readerKind.name,
      sourceAdapterId: entity.handle.source.adapterId,
      supportsSave: entity.supports(ContentCapability.save) || _isReadingType(entity.handle.type),
      supportsDownload: entity.supports(ContentCapability.download) ||
          (!_isReadingType(entity.handle.type) &&
              _readString(
                metadata[_legacyPlayUrlKey],
                fallback: canonicalUri?.toString() ?? '',
              ).isNotEmpty),
    );
  }
}

class LegacySearchSourceContentSearchPort implements ContentSearchPort {
  final String adapterId;
  final SearchSource source;

  const LegacySearchSourceContentSearchPort({
    required this.adapterId,
    required this.source,
  });

  @override
  Future<CursorPage<ContentSearchResult>> search(ContentSearchRequest request) async {
    final page = _parsePage(request.cursor);
    final results = await source.search(
      request.query,
      page: page,
      limit: request.limit,
    );
    final filtered = _applyRequestedTypes(results, request.types);
    return CursorPage(
      items: filtered
          .asMap()
          .entries
          .map(
            (entry) => entry.value.toContentSearchResult(
              adapterId: adapterId,
              score: _descendingScore(entry.key),
            ),
          )
          .toList(growable: false),
    );
  }
}

class LegacyServerContentSearchPort implements ContentSearchPort {
  final String adapterId;
  final ServerSearchSource source;
  final List<String> sources;
  final bool enableWebSupplement;

  const LegacyServerContentSearchPort({
    required this.adapterId,
    required this.source,
    required this.sources,
    required this.enableWebSupplement,
  });

  @override
  Future<CursorPage<ContentSearchResult>> search(ContentSearchRequest request) async {
    final page = _parsePage(request.cursor);
    final results = await source.search(
      request.query,
      page: page,
      limit: request.limit,
      sources: sources,
      mediaTypePreference: _toLegacyMediaTypePreference(request.types),
      enableWebSupplement: enableWebSupplement,
    );
    return CursorPage(
      items: results
          .asMap()
          .entries
          .map(
            (entry) => entry.value.toContentSearchResult(
              adapterId: adapterId,
              score: _descendingScore(entry.key),
            ),
          )
          .toList(growable: false),
    );
  }
}

double _descendingScore(int index) {
  return 1000 - index.toDouble();
}

int _parsePage(String cursor) {
  final parsed = int.tryParse(cursor.trim());
  if (parsed == null || parsed < 1) {
    return 1;
  }
  return parsed;
}

List<SearchResult> _applyRequestedTypes(
  List<SearchResult> results,
  Set<ContentType> requestedTypes,
) {
  if (requestedTypes.isEmpty) {
    return results;
  }
  final allowAudio = requestedTypes.contains(ContentType.audio);
  final allowVideo = requestedTypes.contains(ContentType.video);
  return results.where((result) {
    if (result.mediaType == MediaType.audio) {
      return allowAudio;
    }
    if (result.mediaType == MediaType.video) {
      return allowVideo;
    }
    return true;
  }).toList(growable: false);
}

String? _toLegacyMediaTypePreference(Set<ContentType> requestedTypes) {
  if (requestedTypes.length != 1) {
    return null;
  }
  if (requestedTypes.contains(ContentType.audio)) {
    return 'audio';
  }
  if (requestedTypes.contains(ContentType.video)) {
    return 'video';
  }
  return null;
}

Uri? _parseUri(String raw) {
  final normalized = raw.trim();
  if (normalized.isEmpty) {
    return null;
  }
  return Uri.tryParse(normalized);
}

String _readString(Object? value, {String fallback = ''}) {
  final normalized = '$value'.trim();
  if (normalized.isEmpty || normalized == 'null') {
    return fallback;
  }
  return normalized;
}

String? _readNullableString(Object? value) {
  final normalized = _readString(value);
  return normalized.isEmpty ? null : normalized;
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

MediaType _parseLegacyMediaType(Object? value, {required ContentType fallback}) {
  final normalized = '$value'.trim().toLowerCase();
  if (normalized == MediaType.audio.name || fallback == ContentType.audio) {
    return MediaType.audio;
  }
  return MediaType.video;
}

MediaSubtype _parseLegacyMediaSubtype(
  Object? value, {
  required ContentType fallback,
}) {
  switch ('$value'.trim().toLowerCase()) {
    case 'musictrack':
    case 'music_track':
      return MediaSubtype.musicTrack;
    case 'podcastshow':
    case 'podcast_show':
      return MediaSubtype.podcastShow;
    case 'podcastepisode':
    case 'podcast_episode':
      return MediaSubtype.podcastEpisode;
    default:
      return fallback == ContentType.audio
          ? MediaSubtype.musicTrack
          : MediaSubtype.video;
  }
}

SearchPlaybackKind _parsePlaybackKind(Object? value) {
  switch ('$value'.trim().toLowerCase()) {
    case 'nativestream':
    case 'native_stream':
      return SearchPlaybackKind.nativeStream;
    case 'embeddedweb':
    case 'embedded_web':
      return SearchPlaybackKind.embeddedWeb;
    default:
      return SearchPlaybackKind.externalOpen;
  }
}

ResultAvailability _parseAvailability(Object? value) {
  switch ('$value'.trim().toLowerCase()) {
    case 'preview':
      return ResultAvailability.preview;
    case 'indexedonly':
    case 'indexed_only':
      return ResultAvailability.indexedOnly;
    default:
      return ResultAvailability.available;
  }
}

SourceTier _parseSourceTier(Object? value) {
  switch ('$value'.trim().toLowerCase()) {
    case 'officialapi':
    case 'official_api':
      return SourceTier.officialApi;
    case 'websupplement':
    case 'web_supplement':
      return SourceTier.webSupplement;
    default:
      return SourceTier.publicApi;
  }
}

List<TimedSegment> _parseHighlights(Object? value) {
  if (value is! List) {
    return const [];
  }
  return value
      .whereType<Map>()
      .map(
        (item) => TimedSegment.fromJson(
          Map<String, dynamic>.from(item),
        ),
      )
      .toList(growable: false);
}

bool _isReadingType(ContentType type) {
  switch (type) {
    case ContentType.webArticle:
    case ContentType.rss:
    case ContentType.novel:
    case ContentType.comic:
    case ContentType.subtitle:
      return true;
    default:
      return false;
  }
}
