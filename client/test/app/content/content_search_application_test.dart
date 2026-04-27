import 'package:flutter_test/flutter_test.dart';

import 'package:content_seeker/app/content/content_search_application.dart';
import 'package:content_seeker/core/content/content.dart';
import 'package:content_seeker/features/settings/settings_provider.dart';

void main() {
  group('ContentSearchApplication', () {
    test('returns reading port results even when local sources are unavailable', () async {
      final settings = SettingsProvider();
      settings.setSearchStrategy(SearchStrategy.localOnly);

      const article = ContentSearchResult(
        entity: ContentEntity(
          handle: ContentHandle(
            id: 'article-1',
            canonicalId: 'https://example.com/article-1',
            type: ContentType.webArticle,
            source: ContentSourceRef(
              sourceId: 'reading-hub',
              adapterId: 'reading-hub',
              displayName: 'Reading Hub',
              capabilities: {ContentCapability.search},
            ),
          ),
          title: 'Flutter 架构文章',
          readerKind: ContentReaderKind.webArticle,
          capabilities: {ContentCapability.search},
        ),
        score: 100,
      );

      final app = ContentSearchApplication(
        localSourceRegistry: const {},
        additionalPorts: [
          const _FakeReadingSearchPort(items: [article]),
        ],
      );

      final result = await app.search(
        const ContentSearchRequest(query: 'flutter 架构', limit: 10),
        settings: settings,
      );

      expect(result.errorMessage, isNull);
      expect(result.page.items, hasLength(1));
      expect(result.page.items.first.entity.title, 'Flutter 架构文章');
      expect(
        result.page.items.first.entity.handle.type,
        ContentType.webArticle,
      );
    });
  });
}

class _FakeReadingSearchPort implements ContentSearchPort {
  final List<ContentSearchResult> items;

  const _FakeReadingSearchPort({
    required this.items,
  });

  @override
  Future<CursorPage<ContentSearchResult>> search(
    ContentSearchRequest request,
  ) async {
    return CursorPage(items: items);
  }
}
