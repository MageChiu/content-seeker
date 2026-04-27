// 统一数据模型

import '../core/source_catalog.dart';

enum MediaType { video, audio }

enum MediaSubtype { video, musicTrack, podcastShow, podcastEpisode }

enum SearchPlaybackKind { nativeStream, embeddedWeb, externalOpen }

enum ResultAvailability { available, preview, indexedOnly }

enum SourceTier { officialApi, publicApi, webSupplement }

class TimedSegment {
  final double timestampSeconds;
  final String text;

  TimedSegment({required this.timestampSeconds, required this.text});

  factory TimedSegment.fromJson(Map<String, dynamic> json) => TimedSegment(
        timestampSeconds: (json['timestamp_seconds'] as num).toDouble(),
        text: json['text'] ?? '',
      );
}

class SearchResult {
  final String id;
  final String title;
  final String source;
  final MediaType mediaType;
  final MediaSubtype mediaSubtype;
  final String thumbnailUrl;
  final int durationSeconds;
  final String playUrl;
  final SearchPlaybackKind playbackKind;
  final bool isPlayable;
  final ResultAvailability availability;
  final SourceTier sourceTier;
  final String canonicalUrl;
  final String artistOrAuthor;
  final String albumOrSeries;
  final String description;
  final List<TimedSegment> highlights;
  final String? aiSummary;

  SearchResult({
    required this.id,
    required this.title,
    required this.source,
    required this.mediaType,
    this.mediaSubtype = MediaSubtype.video,
    required this.thumbnailUrl,
    required this.durationSeconds,
    required this.playUrl,
    this.playbackKind = SearchPlaybackKind.externalOpen,
    this.isPlayable = true,
    this.availability = ResultAvailability.available,
    this.sourceTier = SourceTier.publicApi,
    this.canonicalUrl = '',
    this.artistOrAuthor = '',
    this.albumOrSeries = '',
    required this.description,
    this.highlights = const [],
    this.aiSummary,
  });

  SearchResult copyWith({
    String? id,
    String? title,
    String? source,
    MediaType? mediaType,
    MediaSubtype? mediaSubtype,
    String? thumbnailUrl,
    int? durationSeconds,
    String? playUrl,
    SearchPlaybackKind? playbackKind,
    bool? isPlayable,
    ResultAvailability? availability,
    SourceTier? sourceTier,
    String? canonicalUrl,
    String? artistOrAuthor,
    String? albumOrSeries,
    String? description,
    List<TimedSegment>? highlights,
    String? aiSummary,
  }) {
    return SearchResult(
      id: id ?? this.id,
      title: title ?? this.title,
      source: source ?? this.source,
      mediaType: mediaType ?? this.mediaType,
      mediaSubtype: mediaSubtype ?? this.mediaSubtype,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      playUrl: playUrl ?? this.playUrl,
      playbackKind: playbackKind ?? this.playbackKind,
      isPlayable: isPlayable ?? this.isPlayable,
      availability: availability ?? this.availability,
      sourceTier: sourceTier ?? this.sourceTier,
      canonicalUrl: canonicalUrl ?? this.canonicalUrl,
      artistOrAuthor: artistOrAuthor ?? this.artistOrAuthor,
      albumOrSeries: albumOrSeries ?? this.albumOrSeries,
      description: description ?? this.description,
      highlights: highlights ?? this.highlights,
      aiSummary: aiSummary ?? this.aiSummary,
    );
  }

  factory SearchResult.fromJson(Map<String, dynamic> json) => SearchResult(
        id: _readString(json['id']),
        title: _readString(json['title']),
        source: _readString(json['source']),
        mediaType: _parseMediaType(json['media_type'] ?? json['mediaType']),
        mediaSubtype:
            _parseMediaSubtype(json['media_subtype'] ?? json['mediaSubtype']),
        thumbnailUrl:
            _readString(json['thumbnail_url'] ?? json['thumbnailUrl']),
        durationSeconds:
            _readInt(json['duration_seconds'] ?? json['durationSeconds']),
        playUrl: _readString(json['play_url'] ?? json['playUrl']),
        playbackKind: _parsePlaybackKind(
          json['playback_kind'] ?? json['playbackKind'],
        ),
        isPlayable: _readBool(json['is_playable'] ?? json['isPlayable'], true),
        availability: _parseAvailability(
          json['availability'],
        ),
        sourceTier: _parseSourceTier(json['source_tier'] ?? json['sourceTier']),
        canonicalUrl:
            _readString(json['canonical_url'] ?? json['canonicalUrl']),
        artistOrAuthor:
            _readString(json['artist_or_author'] ?? json['artistOrAuthor']),
        albumOrSeries:
            _readString(json['album_or_series'] ?? json['albumOrSeries']),
        description: _readString(json['description']),
        highlights: (json['highlights'] as List?)
                ?.whereType<Map>()
                .map((h) => TimedSegment.fromJson(Map<String, dynamic>.from(h)))
                .toList() ??
            [],
        aiSummary: _readNullableString(json['ai_summary'] ?? json['aiSummary']),
      );

  static MediaType _parseMediaType(Object? value) {
    return '$value'.trim().toLowerCase() == 'audio'
        ? MediaType.audio
        : MediaType.video;
  }

  static MediaSubtype _parseMediaSubtype(Object? value) {
    switch ('$value'.trim().toLowerCase()) {
      case 'music_track':
      case 'musictrack':
        return MediaSubtype.musicTrack;
      case 'podcast_show':
      case 'podcastshow':
        return MediaSubtype.podcastShow;
      case 'podcast_episode':
      case 'podcastepisode':
        return MediaSubtype.podcastEpisode;
      default:
        return MediaSubtype.video;
    }
  }

  static SearchPlaybackKind _parsePlaybackKind(Object? value) {
    switch ('$value'.trim().toLowerCase()) {
      case 'native':
      case 'nativestream':
        return SearchPlaybackKind.nativeStream;
      case 'web_embed':
      case 'embeddedweb':
        return SearchPlaybackKind.embeddedWeb;
      default:
        return SearchPlaybackKind.externalOpen;
    }
  }

  static ResultAvailability _parseAvailability(Object? value) {
    switch ('$value'.trim().toLowerCase()) {
      case 'preview':
        return ResultAvailability.preview;
      case 'indexed_only':
      case 'indexedonly':
        return ResultAvailability.indexedOnly;
      default:
        return ResultAvailability.available;
    }
  }

  static SourceTier _parseSourceTier(Object? value) {
    switch ('$value'.trim().toLowerCase()) {
      case 'official_api':
      case 'officialapi':
        return SourceTier.officialApi;
      case 'web_supplement':
      case 'websupplement':
        return SourceTier.webSupplement;
      default:
        return SourceTier.publicApi;
    }
  }

  static String _readString(Object? value) {
    return value == null ? '' : '$value'.trim();
  }

  static String? _readNullableString(Object? value) {
    final normalized = _readString(value);
    return normalized.isEmpty ? null : normalized;
  }

  static bool _readBool(Object? value, bool fallback) {
    if (value is bool) return value;
    final normalized = '$value'.trim().toLowerCase();
    if (normalized == 'true') return true;
    if (normalized == 'false') return false;
    return fallback;
  }

  static int _readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse('$value') ?? 0;
  }

  String get durationFormatted {
    final h = durationSeconds ~/ 3600;
    final m = (durationSeconds % 3600) ~/ 60;
    final s = durationSeconds % 60;
    if (h > 0) return '$h' 'h${m}m${s}s';
    if (m > 0) return '$m:${s.toString().padLeft(2, '0')}';
    return '0:${s.toString().padLeft(2, '0')}';
  }

  String get sourceKey => source.trim().toLowerCase();

  String get sourceLabel {
    return sourceDescriptor(source).label;
  }

  String get mediaTypeLabel {
    return mediaType == MediaType.video ? '视频' : '音频';
  }

  String get mediaSubtypeLabel {
    switch (mediaSubtype) {
      case MediaSubtype.video:
        return '视频';
      case MediaSubtype.musicTrack:
        return '音乐';
      case MediaSubtype.podcastShow:
        return '播客节目';
      case MediaSubtype.podcastEpisode:
        return '播客单集';
    }
  }

  String get playbackKindLabel {
    switch (playbackKind) {
      case SearchPlaybackKind.nativeStream:
        return '原生流媒体';
      case SearchPlaybackKind.embeddedWeb:
        return '网页内嵌';
      case SearchPlaybackKind.externalOpen:
        return '外部打开';
    }
  }

  String get availabilityLabel {
    switch (availability) {
      case ResultAvailability.available:
        return '可播放';
      case ResultAvailability.preview:
        return '预览';
      case ResultAvailability.indexedOnly:
        return '仅索引';
    }
  }

  String get sourceTierLabel {
    switch (sourceTier) {
      case SourceTier.officialApi:
        return '官方源';
      case SourceTier.publicApi:
        return '公开源';
      case SourceTier.webSupplement:
        return '网页补充';
    }
  }

  bool get hasPlayUrl => playUrl.trim().isNotEmpty;

  bool get hasCanonicalUrl => canonicalUrl.trim().isNotEmpty;

  bool get hasAiSummary => aiSummary?.trim().isNotEmpty == true;

  bool get hasHighlights => highlights.isNotEmpty;

  bool get hasArtistOrAuthor => artistOrAuthor.trim().isNotEmpty;

  bool get hasAlbumOrSeries => albumOrSeries.trim().isNotEmpty;

  String? get metaLine {
    final parts = <String>[
      if (hasArtistOrAuthor) artistOrAuthor.trim(),
      if (hasAlbumOrSeries) albumOrSeries.trim(),
    ];
    if (parts.isEmpty) return null;
    return parts.join(' · ');
  }

  String? get primaryHighlightText {
    if (highlights.isEmpty) return null;
    final text = highlights.first.text.trim();
    return text.isEmpty ? null : text;
  }

  String? get primaryHighlightTimestampLabel {
    if (highlights.isEmpty) return null;
    return _formatTimestamp(highlights.first.timestampSeconds);
  }

  String? get summaryText {
    if (hasAiSummary) return aiSummary!.trim();
    final highlightText = primaryHighlightText;
    if (highlightText != null) return highlightText;
    final normalizedDescription = description.trim();
    if (normalizedDescription.isNotEmpty) return normalizedDescription;
    final normalizedMetaLine = metaLine?.trim();
    if (normalizedMetaLine != null && normalizedMetaLine.isNotEmpty) {
      return normalizedMetaLine;
    }
    return null;
  }

  static String _formatTimestamp(double seconds) {
    final totalSeconds = seconds.isFinite ? seconds.round() : 0;
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
