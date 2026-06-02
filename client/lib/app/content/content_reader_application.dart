import '../../core/content/content.dart';

class ContentReaderSnapshot {
  final List<ContentEntity> featuredItems;
  final List<ContentLibraryEntry> libraryEntries;
  final List<ContentSubscriptionRecord> subscriptions;

  const ContentReaderSnapshot({
    this.featuredItems = const [],
    this.libraryEntries = const [],
    this.subscriptions = const [],
  });
}

class ContentReaderApplication {
  final List<ContentEntity> Function() featuredItemsLoader;
  final ContentDetailPort detailPort;
  final ContentOpenPort openPort;
  final ContentSavePort savePort;
  final ContentLibraryPort libraryPort;
  final ContentSubscriptionPort subscriptionPort;

  const ContentReaderApplication({
    required this.featuredItemsLoader,
    required this.detailPort,
    required this.openPort,
    required this.savePort,
    required this.libraryPort,
    required this.subscriptionPort,
  });

  Future<ContentReaderSnapshot> loadSnapshot({
    ContentLibraryQuery libraryQuery = const ContentLibraryQuery(limit: 100),
    ContentSubscriptionQuery subscriptionQuery =
        const ContentSubscriptionQuery(limit: 100),
  }) async {
    final libraryPage = await libraryPort.list(libraryQuery);
    final subscriptionPage = await subscriptionPort.listSubscriptions(
      subscriptionQuery,
    );
    return ContentReaderSnapshot(
      featuredItems: featuredItemsLoader(),
      libraryEntries: libraryPage.items,
      subscriptions: subscriptionPage.items,
    );
  }

  Future<ContentDetail> getDetail(ContentHandle handle) {
    return detailPort.getDetail(ContentDetailRequest(handle: handle));
  }

  Future<ContentOpenTarget> resolveOpenTarget(
    ContentHandle handle, {
    ContentOpenMode preferredMode = ContentOpenMode.externalBrowser,
    Map<String, Object?> context = const {},
  }) {
    return openPort.resolveOpenTarget(
      ContentOpenRequest(
        handle: handle,
        preferredMode: preferredMode,
        context: context,
      ),
    );
  }

  Future<ContentSaveReceipt> save(
    ContentEntity entity, {
    ContentSaveMode mode = ContentSaveMode.bookmark,
    Map<String, Object?> payload = const {},
  }) {
    return savePort.save(
      ContentSaveRequest(
        entity: entity,
        mode: mode,
        payload: payload,
      ),
    );
  }

  Future<void> removeSaved(String recordId) {
    return savePort.remove(recordId);
  }

  Future<CursorPage<ContentLibraryEntry>> listLibrary(ContentLibraryQuery query) {
    return libraryPort.list(query);
  }

  Future<ContentSubscriptionRecord> subscribe(
    ContentEntity entity, {
    Map<String, Object?> options = const {},
  }) {
    return subscriptionPort.subscribe(
      ContentSubscriptionRequest(
        handle: entity.handle,
        entity: entity,
        options: options,
      ),
    );
  }

  Future<CursorPage<ContentSubscriptionRecord>> listSubscriptions(
    ContentSubscriptionQuery query,
  ) {
    return subscriptionPort.listSubscriptions(query);
  }

  Future<ContentSubscriptionRecord> updateSubscriptionState({
    required String subscriptionId,
    required ContentSubscriptionState state,
  }) {
    return subscriptionPort.updateState(
      subscriptionId: subscriptionId,
      state: state,
    );
  }

  Future<void> unsubscribe(String subscriptionId) {
    return subscriptionPort.unsubscribe(subscriptionId);
  }
}
