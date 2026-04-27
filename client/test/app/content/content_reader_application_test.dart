import 'package:flutter_test/flutter_test.dart';

import 'package:content_seeker/app/content/content_reader_application.dart';
import 'package:content_seeker/core/content/content.dart';

void main() {
  group('ContentReaderApplication', () {
    test('loads snapshot from library and subscription ports', () async {
      final featured = [_entity(id: 'featured-1', type: ContentType.webArticle)];
      const libraryQuery = ContentLibraryQuery(
        limit: 2,
        modes: {ContentSaveMode.favorite},
      );
      const subscriptionQuery = ContentSubscriptionQuery(
        limit: 3,
        states: {ContentSubscriptionState.active},
      );
      final detailPort = _FakeDetailPort(
        detail: ContentDetail(entity: featured.first),
      );
      final openPort = _FakeOpenPort(
        target: ContentOpenTarget(
          handle: featured.first.handle,
          mode: ContentOpenMode.externalBrowser,
          target: Uri.parse('https://example.com/open'),
        ),
      );
      final savePort = _FakeSavePort(
        receipt: ContentSaveReceipt(
          recordId: 'save-1',
          entity: featured.first,
          mode: ContentSaveMode.bookmark,
          savedAt: DateTime(2026),
        ),
      );
      final libraryPort = _FakeLibraryPort(
        page: CursorPage(
          items: [
            ContentLibraryEntry(
              entryId: 'entry-1',
              entity: featured.first,
              mode: ContentSaveMode.favorite,
              createdAt: DateTime(2026, 1, 2),
            ),
          ],
        ),
      );
      final subscriptionPort = _FakeSubscriptionPort(
        page: CursorPage(
          items: [
            ContentSubscriptionRecord(
              subscriptionId: 'sub-1',
              handle: featured.first.handle,
              entity: featured.first,
              state: ContentSubscriptionState.active,
              createdAt: DateTime(2026, 1, 3),
            ),
          ],
        ),
        createdRecord: ContentSubscriptionRecord(
          subscriptionId: 'sub-1',
          handle: featured.first.handle,
          entity: featured.first,
          state: ContentSubscriptionState.active,
          createdAt: DateTime(2026, 1, 3),
        ),
        updatedRecord: ContentSubscriptionRecord(
          subscriptionId: 'sub-1',
          handle: featured.first.handle,
          entity: featured.first,
          state: ContentSubscriptionState.paused,
          createdAt: DateTime(2026, 1, 3),
          updatedAt: DateTime(2026, 1, 4),
        ),
      );
      final application = ContentReaderApplication(
        featuredItemsLoader: () => featured,
        detailPort: detailPort,
        openPort: openPort,
        savePort: savePort,
        libraryPort: libraryPort,
        subscriptionPort: subscriptionPort,
      );

      final snapshot = await application.loadSnapshot(
        libraryQuery: libraryQuery,
        subscriptionQuery: subscriptionQuery,
      );

      expect(snapshot.featuredItems, same(featured));
      expect(snapshot.libraryEntries, hasLength(1));
      expect(snapshot.subscriptions, hasLength(1));
      expect(libraryPort.lastQuery, same(libraryQuery));
      expect(subscriptionPort.lastListQuery, same(subscriptionQuery));
    });

    test('delegates detail open save and subscription operations to ports', () async {
      final entity = _entity(id: 'item-1', type: ContentType.rss);
      final detailPort = _FakeDetailPort(
        detail: ContentDetail(entity: entity, description: 'detail'),
      );
      final openPort = _FakeOpenPort(
        target: ContentOpenTarget(
          handle: entity.handle,
          mode: ContentOpenMode.externalBrowser,
          target: Uri.parse('https://example.com/rss'),
        ),
      );
      final savePort = _FakeSavePort(
        receipt: ContentSaveReceipt(
          recordId: 'save-9',
          entity: entity,
          mode: ContentSaveMode.archive,
          savedAt: DateTime(2026, 2, 1),
        ),
      );
      final libraryPort = _FakeLibraryPort(page: const CursorPage(items: []));
      final subscriptionPort = _FakeSubscriptionPort(
        page: const CursorPage(items: []),
        createdRecord: ContentSubscriptionRecord(
          subscriptionId: 'sub-9',
          handle: entity.handle,
          entity: entity,
          state: ContentSubscriptionState.active,
          createdAt: DateTime(2026, 2, 2),
        ),
        updatedRecord: ContentSubscriptionRecord(
          subscriptionId: 'sub-9',
          handle: entity.handle,
          entity: entity,
          state: ContentSubscriptionState.cancelled,
          createdAt: DateTime(2026, 2, 2),
          updatedAt: DateTime(2026, 2, 3),
        ),
      );
      final application = ContentReaderApplication(
        featuredItemsLoader: () => [entity],
        detailPort: detailPort,
        openPort: openPort,
        savePort: savePort,
        libraryPort: libraryPort,
        subscriptionPort: subscriptionPort,
      );

      final detail = await application.getDetail(entity.handle);
      final openTarget = await application.resolveOpenTarget(
        entity.handle,
        preferredMode: ContentOpenMode.webView,
        context: const {'from': 'test'},
      );
      final saveReceipt = await application.save(
        entity,
        mode: ContentSaveMode.archive,
        payload: const {'source': 'test'},
      );
      final created = await application.subscribe(
        entity,
        options: const {'auto': true},
      );
      final updated = await application.updateSubscriptionState(
        subscriptionId: created.subscriptionId,
        state: ContentSubscriptionState.cancelled,
      );
      await application.removeSaved('save-9');
      await application.unsubscribe('sub-9');

      expect(detail.description, 'detail');
      expect(openTarget.target, Uri.parse('https://example.com/rss'));
      expect(saveReceipt.recordId, 'save-9');
      expect(created.subscriptionId, 'sub-9');
      expect(updated.state, ContentSubscriptionState.cancelled);
      expect(detailPort.lastRequest?.handle.stableId, entity.handle.stableId);
      expect(openPort.lastRequest?.preferredMode, ContentOpenMode.webView);
      expect(openPort.lastRequest?.context, {'from': 'test'});
      expect(savePort.lastSaveRequest?.mode, ContentSaveMode.archive);
      expect(savePort.lastSaveRequest?.payload, {'source': 'test'});
      expect(savePort.lastRemovedId, 'save-9');
      expect(subscriptionPort.lastSubscribeRequest?.handle.stableId,
          entity.handle.stableId);
      expect(subscriptionPort.lastSubscribeRequest?.options, {'auto': true});
      expect(subscriptionPort.lastUpdatedId, 'sub-9');
      expect(
        subscriptionPort.lastUpdatedState,
        ContentSubscriptionState.cancelled,
      );
      expect(subscriptionPort.lastUnsubscribedId, 'sub-9');
    });
  });
}

ContentEntity _entity({
  required String id,
  required ContentType type,
}) {
  return ContentEntity(
    handle: ContentHandle(
      id: id,
      canonicalId: 'sample:$id',
      type: type,
      source: const ContentSourceRef(
        sourceId: 'sample-source',
        adapterId: 'sample-adapter',
        displayName: 'Sample Source',
        capabilities: {
          ContentCapability.detail,
          ContentCapability.open,
          ContentCapability.subscribe,
        },
      ),
    ),
    title: 'Title $id',
    readerKind: type == ContentType.rss
        ? ContentReaderKind.rss
        : ContentReaderKind.webArticle,
    capabilities: const {
      ContentCapability.detail,
      ContentCapability.open,
      ContentCapability.subscribe,
    },
  );
}

class _FakeDetailPort implements ContentDetailPort {
  final ContentDetail detail;
  ContentDetailRequest? lastRequest;

  _FakeDetailPort({required this.detail});

  @override
  Future<ContentDetail> getDetail(ContentDetailRequest request) async {
    lastRequest = request;
    return detail;
  }
}

class _FakeOpenPort implements ContentOpenPort {
  final ContentOpenTarget target;
  ContentOpenRequest? lastRequest;

  _FakeOpenPort({required this.target});

  @override
  Future<ContentOpenTarget> resolveOpenTarget(ContentOpenRequest request) async {
    lastRequest = request;
    return target;
  }
}

class _FakeSavePort implements ContentSavePort {
  final ContentSaveReceipt receipt;
  ContentSaveRequest? lastSaveRequest;
  String? lastRemovedId;

  _FakeSavePort({required this.receipt});

  @override
  Future<void> remove(String recordId) async {
    lastRemovedId = recordId;
  }

  @override
  Future<ContentSaveReceipt> save(ContentSaveRequest request) async {
    lastSaveRequest = request;
    return receipt;
  }
}

class _FakeLibraryPort implements ContentLibraryPort {
  final CursorPage<ContentLibraryEntry> page;
  ContentLibraryQuery? lastQuery;

  _FakeLibraryPort({required this.page});

  @override
  Future<CursorPage<ContentLibraryEntry>> list(ContentLibraryQuery query) async {
    lastQuery = query;
    return page;
  }
}

class _FakeSubscriptionPort implements ContentSubscriptionPort {
  final CursorPage<ContentSubscriptionRecord> page;
  final ContentSubscriptionRecord createdRecord;
  final ContentSubscriptionRecord updatedRecord;
  ContentSubscriptionQuery? lastListQuery;
  ContentSubscriptionRequest? lastSubscribeRequest;
  String? lastUpdatedId;
  ContentSubscriptionState? lastUpdatedState;
  String? lastUnsubscribedId;

  _FakeSubscriptionPort({
    required this.page,
    required this.createdRecord,
    required this.updatedRecord,
  });

  @override
  Future<CursorPage<ContentSubscriptionRecord>> listSubscriptions(
    ContentSubscriptionQuery query,
  ) async {
    lastListQuery = query;
    return page;
  }

  @override
  Future<ContentSubscriptionRecord> subscribe(
    ContentSubscriptionRequest request,
  ) async {
    lastSubscribeRequest = request;
    return createdRecord;
  }

  @override
  Future<void> unsubscribe(String subscriptionId) async {
    lastUnsubscribedId = subscriptionId;
  }

  @override
  Future<ContentSubscriptionRecord> updateState({
    required String subscriptionId,
    required ContentSubscriptionState state,
  }) async {
    lastUpdatedId = subscriptionId;
    lastUpdatedState = state;
    return updatedRecord;
  }
}
