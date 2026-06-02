enum PlaybackKind { nativeStream, embeddedWeb, external }

class PlaybackDescriptor {
  final PlaybackKind kind;
  final String primaryUrl;
  final String? secondaryUrl;
  final String fallbackUrl;
  final String title;
  final String displayLabel;
  final String? mimeType;
  final Map<String, String> headers;

  const PlaybackDescriptor({
    required this.kind,
    required this.primaryUrl,
    this.secondaryUrl,
    required this.fallbackUrl,
    required this.title,
    required this.displayLabel,
    this.mimeType,
    this.headers = const {},
  });
}
