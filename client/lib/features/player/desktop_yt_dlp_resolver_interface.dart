import '../../models/media_playback.dart';
import '../../models/search_result.dart';

abstract class DesktopYtDlpResolver {
  Future<PlaybackDescriptor?> resolve(SearchResult result);
}
