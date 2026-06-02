import '../../domain/media/resolved_media.dart';
import '../../domain/media/source_capability.dart';
import '../../models/media_playback.dart';
import '../../models/play_request.dart';

class LegacyPlaybackDescriptorMapper {
  const LegacyPlaybackDescriptorMapper();

  ResolvedMedia map({
    required PlayRequest request,
    required PlaybackDescriptor descriptor,
  }) {
    final primaryUri = Uri.parse(descriptor.primaryUrl);
    final secondaryUri =
        descriptor.secondaryUrl == null || descriptor.secondaryUrl!.isEmpty
            ? null
            : Uri.parse(descriptor.secondaryUrl!);
    final fallbackUrl = descriptor.fallbackUrl.trim();
    final fallbackUri = fallbackUrl.isEmpty ? null : Uri.parse(fallbackUrl);

    return ResolvedMedia(
      sourceId: request.sourceHint,
      kind: _mapKind(descriptor.kind),
      primaryUri: primaryUri,
      secondaryAudioUri: secondaryUri,
      headers: descriptor.headers,
      title: descriptor.title,
      displayLabel: descriptor.displayLabel,
      mimeType: descriptor.mimeType,
      capability: _buildCapability(descriptor, primaryUri),
      fallbacks: fallbackUri == null
          ? const []
          : [
              FallbackCandidate(
                kind: ResolvedMediaKind.external,
                uri: fallbackUri,
                label: 'legacy-fallback',
              ),
            ],
    );
  }

  ResolvedMediaKind _mapKind(PlaybackKind kind) {
    switch (kind) {
      case PlaybackKind.nativeStream:
        return ResolvedMediaKind.nativeStream;
      case PlaybackKind.embeddedWeb:
        return ResolvedMediaKind.embeddedWeb;
      case PlaybackKind.external:
        return ResolvedMediaKind.external;
    }
  }

  SourceCapability _buildCapability(
    PlaybackDescriptor descriptor,
    Uri primaryUri,
  ) {
    final isNetworkMedia =
        primaryUri.scheme == 'http' || primaryUri.scheme == 'https';
    final supportsDownload =
        descriptor.kind == PlaybackKind.nativeStream && isNetworkMedia;

    return SourceCapability(
      supportsDownload: supportsDownload,
      supportsOffline: supportsDownload,
      supportsProgressiveCache: false,
      requiresAuthentication: descriptor.headers.isNotEmpty,
    );
  }
}
