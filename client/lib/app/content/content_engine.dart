import '../../domain/download/download_task_entity.dart';
import '../../domain/media/playback_session.dart';
import 'content_ports.dart';
import 'content_request.dart';

class ContentEngine {
  final ContentPlaybackPort playbackPort;
  final ContentDownloadPort downloadPort;

  const ContentEngine({
    required this.playbackPort,
    required this.downloadPort,
  });

  Future<PlaybackSession> preparePlayback(ContentRequest request) {
    return playbackPort.prepare(
      request.intent == ContentIntent.playback
          ? request
          : request.copyWith(intent: ContentIntent.playback),
    );
  }

  Future<DownloadTaskEntity> enqueueDownload(ContentRequest request) {
    return downloadPort.enqueue(
      request.intent == ContentIntent.download
          ? request
          : request.copyWith(intent: ContentIntent.download),
    );
  }
}
