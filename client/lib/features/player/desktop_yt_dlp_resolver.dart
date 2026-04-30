import 'desktop_yt_dlp_resolver_interface.dart';
import 'desktop_yt_dlp_resolver_stub.dart'
    if (dart.library.io) 'desktop_yt_dlp_resolver_io.dart';

DesktopYtDlpResolver createDesktopYtDlpResolver() => createDesktopYtDlpResolverImpl();
