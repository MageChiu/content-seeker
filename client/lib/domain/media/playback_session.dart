import 'resolved_media.dart';

class PlaybackSession {
  final String sessionId;
  final String mediaId;
  final ResolvedMedia media;
  final Duration position;
  final double playbackRate;
  final double volume;

  const PlaybackSession({
    required this.sessionId,
    required this.mediaId,
    required this.media,
    this.position = Duration.zero,
    this.playbackRate = 1.0,
    this.volume = 100.0,
  });

  PlaybackSession copyWith({
    String? sessionId,
    String? mediaId,
    ResolvedMedia? media,
    Duration? position,
    double? playbackRate,
    double? volume,
  }) {
    return PlaybackSession(
      sessionId: sessionId ?? this.sessionId,
      mediaId: mediaId ?? this.mediaId,
      media: media ?? this.media,
      position: position ?? this.position,
      playbackRate: playbackRate ?? this.playbackRate,
      volume: volume ?? this.volume,
    );
  }
}
