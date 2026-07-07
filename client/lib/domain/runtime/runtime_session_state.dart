import '../media/media_graph.dart';

enum RuntimeSessionStatus {
  idle,
  resolving,
  ready,
  playing,
  paused,
  buffering,
  ended,
  failed,
}

class RuntimeSessionState {
  final int runtimeId;
  final int sessionId;
  final RuntimeSessionStatus status;
  final MediaGraph? mediaGraph;
  final Duration position;
  final double playbackRate;
  final double volume;
  final String? errorMessage;

  const RuntimeSessionState({
    required this.runtimeId,
    required this.sessionId,
    required this.status,
    this.mediaGraph,
    this.position = Duration.zero,
    this.playbackRate = 1.0,
    this.volume = 100.0,
    this.errorMessage,
  });

  const RuntimeSessionState.idle()
      : runtimeId = 0,
        sessionId = 0,
        status = RuntimeSessionStatus.idle,
        mediaGraph = null,
        position = Duration.zero,
        playbackRate = 1.0,
        volume = 100.0,
        errorMessage = null;

  RuntimeSessionState copyWith({
    int? runtimeId,
    int? sessionId,
    RuntimeSessionStatus? status,
    MediaGraph? mediaGraph,
    Duration? position,
    double? playbackRate,
    double? volume,
    String? errorMessage,
    bool clearError = false,
  }) {
    return RuntimeSessionState(
      runtimeId: runtimeId ?? this.runtimeId,
      sessionId: sessionId ?? this.sessionId,
      status: status ?? this.status,
      mediaGraph: mediaGraph ?? this.mediaGraph,
      position: position ?? this.position,
      playbackRate: playbackRate ?? this.playbackRate,
      volume: volume ?? this.volume,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
