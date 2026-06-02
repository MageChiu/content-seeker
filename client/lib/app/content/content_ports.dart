import '../../domain/download/download_task_entity.dart';
import '../../domain/media/playback_session.dart';
import 'content_request.dart';

abstract class ContentPlaybackPort {
  Future<PlaybackSession> prepare(ContentRequest request);
}

abstract class ContentDownloadPort {
  Future<DownloadTaskEntity> enqueue(ContentRequest request);
}
