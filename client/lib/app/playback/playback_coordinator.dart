import 'package:flutter/foundation.dart';

import '../../domain/errors/playback_error.dart';
import '../../domain/media/playback_session.dart';
import '../../infra/resolver/resolver_orchestrator.dart';
import '../../models/play_request.dart';
import 'playback_state.dart';

class PlaybackCoordinator extends ChangeNotifier {
  PlaybackState _state = PlaybackState.idle;

  PlaybackState get state => _state;

  void setState(PlaybackState nextState) {
    _state = nextState;
    notifyListeners();
  }

  Future<void> prepare({
    required PlayRequest request,
    required ResolverOrchestrator orchestrator,
  }) async {
    setState(const PlaybackState(status: PlaybackStatus.loading));

    try {
      final resolved = await orchestrator.resolve(request);
      setState(
        PlaybackState(
          status: PlaybackStatus.ready,
          session: PlaybackSession(
            sessionId: 'playback-${request.sourceHint}-${request.contentId}',
            mediaId: request.contentId,
            media: resolved,
          ),
        ),
      );
    } catch (error) {
      setState(
        PlaybackState(
          status: PlaybackStatus.failed,
          error: PlaybackError(
            code: 'playback.prepare_failed',
            message: error.toString(),
            cause: error,
          ),
        ),
      );
    }
  }

  void reset() {
    setState(PlaybackState.idle);
  }
}
