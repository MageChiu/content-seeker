import '../../domain/content/content_models.dart';

abstract class ContentSearchPort {
  Future<CursorPage<ContentSearchResult>> search(ContentSearchRequest request);
}

abstract class ContentDetailPort {
  Future<ContentDetail> getDetail(ContentDetailRequest request);
}

abstract class ContentOpenPort {
  Future<ContentOpenTarget> resolveOpenTarget(ContentOpenRequest request);
}

abstract class ContentDownloadPort {
  Future<ContentDownloadPlan> createDownloadPlan(
    ContentDownloadRequest request,
  );
}

abstract class ContentSavePort {
  Future<ContentSaveReceipt> save(ContentSaveRequest request);

  Future<void> remove(String recordId);
}

abstract class ContentLibraryPort {
  Future<CursorPage<ContentLibraryEntry>> list(ContentLibraryQuery query);
}

abstract class ContentSubscriptionPort {
  Future<ContentSubscriptionRecord> subscribe(
    ContentSubscriptionRequest request,
  );

  Future<CursorPage<ContentSubscriptionRecord>> listSubscriptions(
    ContentSubscriptionQuery query,
  );

  Future<ContentSubscriptionRecord> updateState({
    required String subscriptionId,
    required ContentSubscriptionState state,
  });

  Future<void> unsubscribe(String subscriptionId);
}
