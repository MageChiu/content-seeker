import '../../models/media_playback.dart';
import '../../models/search_result.dart';
import 'desktop_yt_dlp_resolver_interface.dart';

class _UnsupportedDesktopYtDlpResolver implements DesktopYtDlpResolver {
  @override
  Future<PlaybackDescriptor?> resolve(SearchResult result) async => null;
}

DesktopYtDlpResolver createDesktopYtDlpResolverImpl() =>
    _UnsupportedDesktopYtDlpResolver();
