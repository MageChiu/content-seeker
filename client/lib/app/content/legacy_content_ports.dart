import '../../domain/download/download_task_entity.dart';
import '../../domain/media/playback_session.dart';
import '../download/download_coordinator.dart';
import '../playback/playback_coordinator.dart';
import '../../infra/resolver/resolver_orchestrator.dart';
import 'content_bridge.dart';
import 'content_ports.dart';
import 'content_request.dart';

class LegacyContentPlaybackPort implements ContentPlaybackPort {
  final PlaybackCoordinator playbackCoordinator;
  final ResolverOrchestrator resolverOrchestrator;

  const LegacyContentPlaybackPort({
    required this.playbackCoordinator,
    required this.resolverOrchestrator,
  });

  @override
  Future<PlaybackSession> prepare(ContentRequest request) async {
    final playbackRequest = request.copyWith(intent: ContentIntent.playback);
    await playbackCoordinator.prepare(
      request: playbackRequest.toLegacyPlayRequest(),
      orchestrator: resolverOrchestrator,
    );
    final session = playbackCoordinator.state.session;
    if (session == null) {
      throw StateError('统一内容播放端口未返回有效播放会话。');
    }
    return session;
  }
}

class LegacyContentDownloadPort implements ContentDownloadPort {
  final DownloadCoordinator downloadCoordinator;

  const LegacyContentDownloadPort({
    required this.downloadCoordinator,
  });

  @override
  Future<DownloadTaskEntity> enqueue(ContentRequest request) {
    final downloadRequest = request.copyWith(intent: ContentIntent.download);
    return downloadCoordinator.enqueue(downloadRequest.toLegacyDownloadRequest());
  }
}
