import '../../../core/search_source.dart';
import '../../../models/search_result.dart';
import 'bilibili_search_engine.dart';

class BilibiliLocalSource implements SearchSource {
  final BilibiliSearchEngine _engine;

  BilibiliLocalSource({
    Map<String, String> credentials = const <String, String>{},
  }) : _engine = BilibiliSearchEngine(credentials: credentials);

  @override
  String get name => 'bilibili_local';

  @override
  bool get isConfigured => true;

  @override
  Future<List<SearchResult>> search(
    String query, {
    int page = 1,
    int limit = 20,
  }) {
    return _engine.searchVideos(
      query,
      page: page,
      limit: limit,
    );
  }
}
