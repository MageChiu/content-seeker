import '../../core/content/content.dart';

class InMemoryContentStore
    implements ContentSavePort, ContentLibraryPort, ContentSubscriptionPort {
  final Map<String, ContentLibraryEntry> _libraryEntriesById = {};
  final Map<String, ContentSubscriptionRecord> _subscriptionsById = {};
  int _nextSaveId = 0;
  int _nextSubscriptionId = 0;

  @override
  Future<ContentSaveReceipt> save(ContentSaveRequest request) async {
    final existing = _findLibraryEntry(
      stableId: request.entity.handle.stableId,
      mode: request.mode,
    );
    if (existing != null) {
      return ContentSaveReceipt(
        recordId: existing.entryId,
        entity: existing.entity,
        mode: existing.mode,
        savedAt: existing.createdAt,
      );
    }

    final savedAt = DateTime.now();
    final entryId = 'save_${++_nextSaveId}';
    final entry = ContentLibraryEntry(
      entryId: entryId,
      entity: request.entity,
      mode: request.mode,
      createdAt: savedAt,
    );
    _libraryEntriesById[entryId] = entry;

    return ContentSaveReceipt(
      recordId: entryId,
      entity: request.entity,
      mode: request.mode,
      savedAt: savedAt,
    );
  }

  @override
  Future<void> remove(String recordId) async {
    _libraryEntriesById.remove(recordId);
  }

  @override
  Future<CursorPage<ContentLibraryEntry>> list(
      ContentLibraryQuery query) async {
    final filtered = _libraryEntriesById.values.where((entry) {
      final modeMatched =
          query.modes.isEmpty || query.modes.contains(entry.mode);
      final typeMatched =
          query.types.isEmpty || query.types.contains(entry.entity.handle.type);
      return modeMatched && typeMatched;
    }).toList(growable: false)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final offset = int.tryParse(query.cursor) ?? 0;
    final safeOffset = offset.clamp(0, filtered.length);
    final end = (safeOffset + query.limit).clamp(0, filtered.length);
    final items = filtered.sublist(safeOffset, end);

    return CursorPage(
      items: items,
      nextCursor: end < filtered.length ? '$end' : '',
      hasMore: end < filtered.length,
    );
  }

  @override
  Future<ContentSubscriptionRecord> subscribe(
    ContentSubscriptionRequest request,
  ) async {
    final existing = _findSubscriptionByStableId(request.handle.stableId);
    if (existing != null) {
      if (existing.state == ContentSubscriptionState.active) {
        return existing;
      }
      return updateState(
        subscriptionId: existing.subscriptionId,
        state: ContentSubscriptionState.active,
      );
    }

    final now = DateTime.now();
    final record = ContentSubscriptionRecord(
      subscriptionId: 'sub_${++_nextSubscriptionId}',
      handle: request.handle,
      entity: request.entity,
      state: ContentSubscriptionState.active,
      createdAt: now,
      updatedAt: now,
    );
    _subscriptionsById[record.subscriptionId] = record;
    return record;
  }

  @override
  Future<CursorPage<ContentSubscriptionRecord>> listSubscriptions(
    ContentSubscriptionQuery query,
  ) async {
    final filtered = _subscriptionsById.values.where((record) {
      final stateMatched =
          query.states.isEmpty || query.states.contains(record.state);
      final typeMatched =
          query.types.isEmpty || query.types.contains(record.handle.type);
      final sourceMatched = query.sourceIds.isEmpty ||
          query.sourceIds.contains(record.handle.source.sourceId);
      return stateMatched && typeMatched && sourceMatched;
    }).toList(growable: false)
      ..sort((a, b) {
        final left = a.updatedAt ?? a.createdAt;
        final right = b.updatedAt ?? b.createdAt;
        return right.compareTo(left);
      });

    final offset = int.tryParse(query.cursor) ?? 0;
    final safeOffset = offset.clamp(0, filtered.length);
    final end = (safeOffset + query.limit).clamp(0, filtered.length);
    final items = filtered.sublist(safeOffset, end);

    return CursorPage(
      items: items,
      nextCursor: end < filtered.length ? '$end' : '',
      hasMore: end < filtered.length,
    );
  }

  @override
  Future<ContentSubscriptionRecord> updateState({
    required String subscriptionId,
    required ContentSubscriptionState state,
  }) async {
    final existing = _subscriptionsById[subscriptionId];
    if (existing == null) {
      throw StateError('未找到订阅记录: $subscriptionId');
    }
    final updated = ContentSubscriptionRecord(
      subscriptionId: existing.subscriptionId,
      handle: existing.handle,
      entity: existing.entity,
      state: state,
      createdAt: existing.createdAt,
      updatedAt: DateTime.now(),
    );
    _subscriptionsById[subscriptionId] = updated;
    return updated;
  }

  @override
  Future<void> unsubscribe(String subscriptionId) async {
    _subscriptionsById.remove(subscriptionId);
  }
  ContentLibraryEntry? _findLibraryEntry({
    required String stableId,
    required ContentSaveMode mode,
  }) {
    for (final entry in _libraryEntriesById.values) {
      if (entry.entity.handle.stableId == stableId && entry.mode == mode) {
        return entry;
      }
    }
    return null;
  }

  ContentSubscriptionRecord? _findSubscriptionByStableId(String stableId) {
    for (final record in _subscriptionsById.values) {
      if (record.handle.stableId == stableId) {
        return record;
      }
    }
    return null;
  }
}
