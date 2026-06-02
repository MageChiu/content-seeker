import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/content/content.dart';
import '../../domain/download/offline_asset.dart';
import '../../platform/storage/app_storage_paths.dart';
import '../download/offline_asset_repository.dart';
import 'content_json_codec.dart';

class PersistentContentStore
    implements
        ContentSavePort,
        ContentLibraryPort,
        ContentSubscriptionPort,
        ContentDetailPort {
  final AppStoragePaths storagePaths;
  final OfflineAssetRepository offlineAssetRepository;

  List<ContentLibraryEntry>? _libraryCache;
  List<ContentSubscriptionRecord>? _subscriptionCache;

  PersistentContentStore({
    this.storagePaths = const AppStoragePaths(),
    required this.offlineAssetRepository,
  });

  @override
  Future<ContentSaveReceipt> save(ContentSaveRequest request) async {
    final libraryEntries = await _loadLibraryEntries();
    final existing = _findLibraryEntry(
      entries: libraryEntries,
      stableId: request.entity.handle.stableId,
      mode: request.mode,
    );

    final detail = request.payload['detail'];
    final snapshot = detail is ContentDetail ? detail : null;
    final snapshotPath = snapshot == null
        ? existing?.snapshotPath ?? ''
        : await _writeSnapshot(snapshot);
    final offlineAssetId = snapshot == null
        ? existing?.offlineAssetId ?? ''
        : await _registerSnapshotAsset(snapshot, snapshotPath);

    if (existing != null) {
      final updated = ContentLibraryEntry(
        entryId: existing.entryId,
        entity: request.entity,
        mode: existing.mode,
        createdAt: existing.createdAt,
        snapshotPath: snapshotPath,
        offlineAssetId: offlineAssetId,
      );
      final index =
          libraryEntries.indexWhere((entry) => entry.entryId == existing.entryId);
      libraryEntries[index] = updated;
      await _persistLibraryEntries(libraryEntries);
      return ContentSaveReceipt(
        recordId: updated.entryId,
        entity: updated.entity,
        mode: updated.mode,
        savedAt: updated.createdAt,
        snapshotPath: updated.snapshotPath,
        offlineAssetId: updated.offlineAssetId,
      );
    }

    final savedAt = DateTime.now();
    final entry = ContentLibraryEntry(
      entryId: 'save_${savedAt.microsecondsSinceEpoch}',
      entity: request.entity,
      mode: request.mode,
      createdAt: savedAt,
      snapshotPath: snapshotPath,
      offlineAssetId: offlineAssetId,
    );
    libraryEntries.add(entry);
    await _persistLibraryEntries(libraryEntries);

    return ContentSaveReceipt(
      recordId: entry.entryId,
      entity: entry.entity,
      mode: entry.mode,
      savedAt: entry.createdAt,
      snapshotPath: entry.snapshotPath,
      offlineAssetId: entry.offlineAssetId,
    );
  }

  @override
  Future<void> remove(String recordId) async {
    final entries = await _loadLibraryEntries();
    final index = entries.indexWhere((entry) => entry.entryId == recordId);
    if (index < 0) {
      return;
    }
    final removed = entries.removeAt(index);
    if (removed.snapshotPath.isNotEmpty) {
      final file = File(removed.snapshotPath);
      if (await file.exists()) {
        await file.delete();
      }
    }
    if (removed.offlineAssetId.isNotEmpty) {
      await offlineAssetRepository.removeAsset(removed.offlineAssetId);
    }
    await _persistLibraryEntries(entries);
  }

  @override
  Future<CursorPage<ContentLibraryEntry>> list(ContentLibraryQuery query) async {
    final filtered = (await _loadLibraryEntries()).where((entry) {
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
    return CursorPage(
      items: filtered.sublist(safeOffset, end),
      nextCursor: end < filtered.length ? '$end' : '',
      hasMore: end < filtered.length,
    );
  }

  @override
  Future<ContentSubscriptionRecord> subscribe(
    ContentSubscriptionRequest request,
  ) async {
    final subscriptions = await _loadSubscriptions();
    final existing = _findSubscription(
      subscriptions,
      request.handle.stableId,
    );
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
      subscriptionId: 'sub_${now.microsecondsSinceEpoch}',
      handle: request.handle,
      entity: request.entity,
      state: ContentSubscriptionState.active,
      createdAt: now,
      updatedAt: now,
    );
    subscriptions.add(record);
    await _persistSubscriptions(subscriptions);
    return record;
  }

  @override
  Future<CursorPage<ContentSubscriptionRecord>> listSubscriptions(
    ContentSubscriptionQuery query,
  ) async {
    final filtered = (await _loadSubscriptions()).where((record) {
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
    return CursorPage(
      items: filtered.sublist(safeOffset, end),
      nextCursor: end < filtered.length ? '$end' : '',
      hasMore: end < filtered.length,
    );
  }

  @override
  Future<ContentSubscriptionRecord> updateState({
    required String subscriptionId,
    required ContentSubscriptionState state,
  }) async {
    final subscriptions = await _loadSubscriptions();
    final index = subscriptions.indexWhere(
      (record) => record.subscriptionId == subscriptionId,
    );
    if (index < 0) {
      throw StateError('未找到订阅记录: $subscriptionId');
    }
    final existing = subscriptions[index];
    final updated = ContentSubscriptionRecord(
      subscriptionId: existing.subscriptionId,
      handle: existing.handle,
      entity: existing.entity,
      state: state,
      createdAt: existing.createdAt,
      updatedAt: DateTime.now(),
    );
    subscriptions[index] = updated;
    await _persistSubscriptions(subscriptions);
    return updated;
  }

  @override
  Future<void> unsubscribe(String subscriptionId) async {
    final subscriptions = await _loadSubscriptions();
    subscriptions.removeWhere((record) => record.subscriptionId == subscriptionId);
    await _persistSubscriptions(subscriptions);
  }

  @override
  Future<ContentDetail> getDetail(ContentDetailRequest request) async {
    final entries = await _loadLibraryEntries();
    final matched = entries.firstWhere(
      (entry) => entry.entity.handle.stableId == request.handle.stableId,
      orElse: () => throw StateError('未找到离线内容详情: ${request.handle.stableId}'),
    );
    if (matched.snapshotPath.isEmpty) {
      throw StateError('当前内容尚未保存离线快照: ${request.handle.stableId}');
    }
    final file = File(matched.snapshotPath);
    if (!await file.exists()) {
      throw StateError('离线快照文件不存在: ${matched.snapshotPath}');
    }
    final raw = await file.readAsString();
    return decodeContentDetail(
      Map<String, dynamic>.from(jsonDecode(raw) as Map),
    );
  }

  Future<List<ContentLibraryEntry>> _loadLibraryEntries() async {
    if (_libraryCache != null) {
      return _libraryCache!;
    }
    final file = await _libraryFile();
    if (!await file.exists()) {
      _libraryCache = <ContentLibraryEntry>[];
      return _libraryCache!;
    }
    final raw = await file.readAsString();
    if (raw.trim().isEmpty) {
      _libraryCache = <ContentLibraryEntry>[];
      return _libraryCache!;
    }
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      _libraryCache = <ContentLibraryEntry>[];
      return _libraryCache!;
    }
    _libraryCache = decoded
        .whereType<Map>()
        .map((item) => decodeLibraryEntry(Map<String, dynamic>.from(item)))
        .toList(growable: true);
    return _libraryCache!;
  }

  Future<List<ContentSubscriptionRecord>> _loadSubscriptions() async {
    if (_subscriptionCache != null) {
      return _subscriptionCache!;
    }
    final file = await _subscriptionsFile();
    if (!await file.exists()) {
      _subscriptionCache = <ContentSubscriptionRecord>[];
      return _subscriptionCache!;
    }
    final raw = await file.readAsString();
    if (raw.trim().isEmpty) {
      _subscriptionCache = <ContentSubscriptionRecord>[];
      return _subscriptionCache!;
    }
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      _subscriptionCache = <ContentSubscriptionRecord>[];
      return _subscriptionCache!;
    }
    _subscriptionCache = decoded
        .whereType<Map>()
        .map(
          (item) => decodeSubscriptionRecord(Map<String, dynamic>.from(item)),
        )
        .toList(growable: true);
    return _subscriptionCache!;
  }

  Future<void> _persistLibraryEntries(List<ContentLibraryEntry> entries) async {
    final file = await _libraryFile();
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(
        entries.map(encodeLibraryEntry).toList(growable: false),
      ),
    );
    _libraryCache = entries;
  }

  Future<void> _persistSubscriptions(
    List<ContentSubscriptionRecord> subscriptions,
  ) async {
    final file = await _subscriptionsFile();
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(
        subscriptions.map(encodeSubscriptionRecord).toList(growable: false),
      ),
    );
    _subscriptionCache = subscriptions;
  }

  Future<File> _libraryFile() {
    return storagePaths.metadataFile('content_library.json');
  }

  Future<File> _subscriptionsFile() {
    return storagePaths.metadataFile('content_subscriptions.json');
  }

  Future<String> _writeSnapshot(ContentDetail detail) async {
    final snapshotsDir = await storagePaths.snapshotsRoot();
    final file = File(
      p.join(
        snapshotsDir.path,
        '${_sanitizeSegment(detail.entity.handle.stableId)}.json',
      ),
    );
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(
        encodeContentDetail(detail),
      ),
    );
    return file.path;
  }

  Future<String> _registerSnapshotAsset(
    ContentDetail detail,
    String snapshotPath,
  ) async {
    final file = File(snapshotPath);
    final assetId =
        'snapshot-${_sanitizeSegment(detail.entity.handle.stableId)}';
    final fileSize = await file.length();
    await offlineAssetRepository.saveAsset(
      OfflineAsset(
        assetId: assetId,
        mediaId: detail.entity.handle.stableId,
        sourceId: detail.entity.handle.source.sourceId,
        title: detail.entity.title,
        kind: OfflineAssetKind.snapshot,
        localPath: snapshotPath,
        mimeType: 'application/json',
        durationMs: detail.entity.duration?.inMilliseconds ?? 0,
        fileSizeBytes: fileSize,
        contentType: detail.entity.handle.type.name,
        originalUrl: detail.entity.canonicalUri?.toString() ?? '',
        createdAt: DateTime.now(),
      ),
    );
    return assetId;
  }

  ContentLibraryEntry? _findLibraryEntry({
    required List<ContentLibraryEntry> entries,
    required String stableId,
    required ContentSaveMode mode,
  }) {
    for (final entry in entries) {
      if (entry.entity.handle.stableId == stableId && entry.mode == mode) {
        return entry;
      }
    }
    return null;
  }

  ContentSubscriptionRecord? _findSubscription(
    List<ContentSubscriptionRecord> subscriptions,
    String stableId,
  ) {
    for (final item in subscriptions) {
      if (item.handle.stableId == stableId) {
        return item;
      }
    }
    return null;
  }

  String _sanitizeSegment(String input) {
    return input.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  }
}
