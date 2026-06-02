import '../features/settings/settings_provider.dart';
import 'search_source.dart';
import '../features/search/sources/youtube_local_source.dart';
import '../features/search/sources/bilibili_local_source.dart';
import '../features/search/sources/dailymotion_local_source.dart';
import '../features/search/sources/deezer_local_source.dart';
import '../features/search/sources/internet_archive_local_source.dart';
import '../features/search/sources/internet_archive_video_local_source.dart';
import '../features/search/sources/itunes_local_source.dart';
import '../features/search/sources/jamendo_local_source.dart';
import '../features/search/sources/vimeo_local_source.dart';
import '../features/search/sources/peertube_local_source.dart';
import '../features/search/sources/acfun_local_source.dart';
import '../features/search/sources/youku_local_source.dart';

/// 本地源工厂函数签名
typedef SearchSourceFactory = SearchSource Function(SourceConfig config);

/// 本地搜索源注册表：新增源只需要在此注册
final Map<String, SearchSourceFactory> kLocalSourceRegistry = {
  'youtube': (config) => YouTubeLocalSource(
        apiKey: config.credentials['apiKey'] ?? '',
      ),
  'bilibili': (config) => BilibiliLocalSource(
        credentials: config.credentials,
      ),
  'dailymotion': (_) => DailymotionLocalSource(),
  'itunes': (_) => ItunesLocalSource(),
  'deezer': (_) => DeezerLocalSource(),
  'internet_archive': (_) => InternetArchiveLocalSource(),
  'internet_archive_video': (_) => InternetArchiveVideoLocalSource(),
  'jamendo': (config) => JamendoLocalSource(
        clientId: config.credentials['apiKey'] ?? '',
      ),
  'vimeo': (config) => VimeoLocalSource(
        accessToken: config.credentials['accessToken'] ?? '',
      ),
  'peertube': (config) => PeerTubeLocalSource(
        instanceUrl: config.customBaseUrl,
      ),
  'acfun': (_) => AcFunLocalSource(),
  'youku': (config) => YoukuLocalSource(
        clientId: config.credentials['clientId'] ?? '',
      ),
};
