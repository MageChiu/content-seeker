import '../../domain/errors/playback_error.dart';
import '../../domain/media/playback_session.dart';

enum PlaybackStatus { idle, loading, ready, buffering, failed, completed }

class PlaybackState {
  final PlaybackStatus status;
  final PlaybackSession? session;
  final PlaybackError? error;

  const PlaybackState({
    required this.status,
    this.session,
    this.error,
  });

  static const idle = PlaybackState(status: PlaybackStatus.idle);
}
