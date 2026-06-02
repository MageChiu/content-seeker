import 'package:flutter_test/flutter_test.dart';

import 'package:content_seeker/core/content/content.dart';
import 'package:content_seeker/infra/content/in_memory_content_store.dart';

void main() {
  group('InMemoryContentStore', () {
    test('deduplicates saves by stable id and mode', () async {
      final store = InMemoryContentStore();
      final entity = _entity(
        id: 'same-id',
        canonicalId: 'sample:same-id',
        type: ContentType.webArticle,
      );

      final first = await store.save(
        ContentSaveRequest(entity: entity, mode: ContentSaveMode.bookmark),
      );
      final duplicate = await store.save(
        ContentSaveRequest(entity: entity, mode: ContentSaveMode.bookmark),
      );
      final secondMode = await store.save(
        ContentSaveRequest(entity: entity, mode: ContentSaveMode.favorite),
      );
      final page = await store.list(const ContentLibraryQuery(limit: 10));

      expect(duplicate.recordId, first.recordId);
      expect(secondMode.recordId, isNot(first.recordId));
      expect(page.items.length, 2);
    });

    test('lists library entries with filters and cursor pagination', () async {
      final store = InMemoryContentStore();

      await store.save(
        ContentSaveRequest(
          entity: _entity(id: 'article-1', type: ContentType.webArticle),
          mode: ContentSaveMode.bookmark,
        ),
      );
      await store.save(
        ContentSaveRequest(
          entity: _entity(id: 'novel-1', type: ContentType.novel),
          mode: ContentSaveMode.favorite,
        ),
      );
      await store.save(
        ContentSaveRequest(
          entity: _entity(id: 'comic-1', type: ContentType.comic),
          mode: ContentSaveMode.favorite,
        ),
      );

      final favoriteOnly = await store.list(
        const ContentLibraryQuery(
          limit: 10,
          modes: {ContentSaveMode.favorite},
        ),
      );
      final firstPage = await store.list(const ContentLibraryQuery(limit: 1));
      final secondPage = await store.list(
        ContentLibraryQuery(limit: 10, cursor: firstPage.nextCursor),
      );

      expect(favoriteOnly.items.map((entry) => entry.entity.handle.type), {
        ContentType.novel,
        ContentType.comic,
      });
      expect(firstPage.items, hasLength(1));
      expect(firstPage.hasMore, isTrue);
      expect(firstPage.nextCursor, '1');
      expect(secondPage.items, hasLength(2));
      expect(secondPage.hasMore, isFalse);
    });

    test('reactivates existing subscription instead of creating a new one', () async {
      final store = InMemoryContentStore();
      final entity = _entity(
        id: 'rss-1',
        canonicalId: 'sample:rss-1',
        type: ContentType.rss,
      );

      final first = await store.subscribe(
        ContentSubscriptionRequest(handle: entity.handle, entity: entity),
      );
      await store.updateState(
        subscriptionId: first.subscriptionId,
        state: ContentSubscriptionState.paused,
      );

      final resumed = await store.subscribe(
        ContentSubscriptionRequest(handle: entity.handle, entity: entity),
      );
      final page = await store.listSubscriptions(
        const ContentSubscriptionQuery(limit: 10),
      );

      expect(resumed.subscriptionId, first.subscriptionId);
      expect(resumed.state, ContentSubscriptionState.active);
      expect(page.items, hasLength(1));
    });
  });
}

ContentEntity _entity({
  required String id,
  String canonicalId = '',
  required ContentType type,
}) {
  return ContentEntity(
    handle: ContentHandle(
      id: id,
      canonicalId: canonicalId,
      type: type,
      source: const ContentSourceRef(
        sourceId: 'sample-source',
        adapterId: 'sample-adapter',
        displayName: 'Sample',
      ),
    ),
    title: 'Title $id',
    readerKind: ContentReaderKind.webArticle,
    capabilities: const {
      ContentCapability.detail,
      ContentCapability.open,
      ContentCapability.subscribe,
    },
  );
}
