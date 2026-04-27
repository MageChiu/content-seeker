enum ContentIntent { playback, download }

enum ContentMediaType { unknown, video, audio }

class ContentRequest {
  final ContentIntent intent;
  final String contentId;
  final String sourceId;
  final String title;
  final ContentMediaType mediaType;
  final Uri? primaryUri;
  final Uri? fallbackUri;
  final String sourceLabel;
  final String thumbnailUrl;
  final int durationSeconds;
  final String description;
  final String filename;
  final Map<String, String> headers;
  final Map<String, Object?> attributes;

  const ContentRequest({
    required this.intent,
    required this.contentId,
    required this.sourceId,
    required this.title,
    this.mediaType = ContentMediaType.unknown,
    this.primaryUri,
    this.fallbackUri,
    this.sourceLabel = '',
    this.thumbnailUrl = '',
    this.durationSeconds = 0,
    this.description = '',
    this.filename = '',
    this.headers = const {},
    this.attributes = const {},
  });

  bool get hasPrimaryUri => primaryUri != null;

  bool get hasFallbackUri => fallbackUri != null;

  String get stableId {
    final normalizedSource = sourceId.trim();
    final normalizedContent = contentId.trim();
    if (normalizedSource.isEmpty) {
      return normalizedContent;
    }
    if (normalizedContent.isEmpty) {
      return normalizedSource;
    }
    return '$normalizedSource-$normalizedContent';
  }

  ContentRequest copyWith({
    ContentIntent? intent,
    String? contentId,
    String? sourceId,
    String? title,
    ContentMediaType? mediaType,
    Uri? primaryUri,
    Uri? fallbackUri,
    String? sourceLabel,
    String? thumbnailUrl,
    int? durationSeconds,
    String? description,
    String? filename,
    Map<String, String>? headers,
    Map<String, Object?>? attributes,
  }) {
    return ContentRequest(
      intent: intent ?? this.intent,
      contentId: contentId ?? this.contentId,
      sourceId: sourceId ?? this.sourceId,
      title: title ?? this.title,
      mediaType: mediaType ?? this.mediaType,
      primaryUri: primaryUri ?? this.primaryUri,
      fallbackUri: fallbackUri ?? this.fallbackUri,
      sourceLabel: sourceLabel ?? this.sourceLabel,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      description: description ?? this.description,
      filename: filename ?? this.filename,
      headers: headers ?? this.headers,
      attributes: attributes ?? this.attributes,
    );
  }
}
