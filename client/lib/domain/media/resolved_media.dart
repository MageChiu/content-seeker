import 'source_capability.dart';

enum ResolvedMediaKind { nativeStream, embeddedWeb, external }

class FallbackCandidate {
  final ResolvedMediaKind kind;
  final Uri uri;
  final Map<String, String> headers;
  final String label;

  const FallbackCandidate({
    required this.kind,
    required this.uri,
    this.headers = const {},
    this.label = '',
  });
}

class ResolvedMedia {
  final String sourceId;
  final ResolvedMediaKind kind;
  final Uri primaryUri;
  final Uri? secondaryAudioUri;
  final Uri? subtitleUri;
  final Map<String, String> headers;
  final DateTime? expiresAt;
  final List<FallbackCandidate> fallbacks;
  final SourceCapability capability;
  final String title;
  final String displayLabel;
  final String? mimeType;

  const ResolvedMedia({
    required this.sourceId,
    required this.kind,
    required this.primaryUri,
    this.secondaryAudioUri,
    this.subtitleUri,
    this.headers = const {},
    this.expiresAt,
    this.fallbacks = const [],
    this.capability = const SourceCapability(),
    this.title = '',
    this.displayLabel = '',
    this.mimeType,
  });

  bool get supportsDownload => capability.supportsDownload;
  bool get supportsOffline => capability.supportsOffline;
  bool get supportsProgressiveCache => capability.supportsProgressiveCache;

  Uri? get fallbackUri {
    for (final fallback in fallbacks) {
      if (fallback.kind == ResolvedMediaKind.external) {
        return fallback.uri;
      }
    }
    return null;
  }

  String get fallbackUrl => fallbackUri?.toString() ?? '';
}
