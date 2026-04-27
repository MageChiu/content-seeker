// 搜索源抽象接口
import '../models/search_result.dart';

abstract class SearchSource {
  String get name;
  bool get isConfigured;
  Future<List<SearchResult>> search(String query, {int page, int limit});
}
