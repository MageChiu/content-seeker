import '../../domain/media/resolved_media.dart';
import '../../features/player/playback_resolver.dart';
import '../../models/play_request.dart';
import 'legacy_playback_descriptor_mapper.dart';
import 'resolver_strategy.dart';

class LegacyPlaybackResolverStrategy implements ResolverStrategy {
  final PlaybackResolver playbackResolver;
  final LegacyPlaybackDescriptorMapper mapper;

  const LegacyPlaybackResolverStrategy({
    this.playbackResolver = const PlaybackResolver(),
    this.mapper = const LegacyPlaybackDescriptorMapper(),
  });

  @override
  Future<ResolvedMedia?> resolve(PlayRequest request) async {
    final descriptor = await playbackResolver.resolve(request);
    return mapper.map(request: request, descriptor: descriptor);
  }
}
