import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../app/content/content_reader_application.dart';
import '../../core/content/content.dart';
import '../settings/settings_provider.dart';

class ReaderProvider extends ChangeNotifier {
  final ContentReaderApplication application;

  ReaderProvider({
    required this.application,
  }) {
    unawaited(refresh());
  }

  List<ContentEntity> _featuredItems = const [];
  List<ContentLibraryEntry> _libraryEntries = const [];
  List<ContentSubscriptionRecord> _subscriptions = const [];
  bool _loading = false;
  String? _error;
  String _rssFeedSignature = '';

  List<ContentEntity> get featuredItems => _featuredItems;
  List<ContentLibraryEntry> get libraryEntries => _libraryEntries;
  List<ContentSubscriptionRecord> get subscriptions => _subscriptions;
  bool get loading => _loading;
  String? get error => _error;

  void updateSettings(SettingsProvider settings) {
    if (_rssFeedSignature == settings.rssFeedSignature) {
      return;
    }
    _rssFeedSignature = settings.rssFeedSignature;
    unawaited(refresh());
  }

  int get activeSubscriptionCount => _subscriptions
      .where((record) => record.state == ContentSubscriptionState.active)
      .length;

  bool isSaved(ContentHandle handle) {
    return _libraryEntries.any(
      (entry) => entry.entity.handle.stableId == handle.stableId,
    );
  }

  ContentLibraryEntry? libraryEntryForHandle(ContentHandle handle) {
    for (final entry in _libraryEntries) {
      if (entry.entity.handle.stableId == handle.stableId) {
        return entry;
      }
    }
    return null;
  }

  ContentSubscriptionRecord? subscriptionForHandle(ContentHandle handle) {
    for (final record in _subscriptions) {
      if (record.handle.stableId == handle.stableId) {
        return record;
      }
    }
    return null;
  }

  Future<void> refresh() async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final snapshot = await application.loadSnapshot();
      _featuredItems = snapshot.featuredItems;
      _libraryEntries = snapshot.libraryEntries;
      _subscriptions = snapshot.subscriptions;
    } catch (e) {
      _error = '阅读数据加载失败: $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<ContentDetail> loadDetail(ContentHandle handle) {
    return application.getDetail(handle);
  }

  Future<ContentOpenTarget> resolveOpenTarget(ContentHandle handle) {
    return application.resolveOpenTarget(
      handle,
      preferredMode: ContentOpenMode.externalBrowser,
    );
  }

  Future<ContentSaveReceipt> save(ContentEntity entity) async {
    final receipt = await application.save(entity);
    await refresh();
    return receipt;
  }

  Future<ContentSaveReceipt> saveDetail(ContentDetail detail) async {
    final receipt = await application.save(
      detail.entity,
      payload: {'detail': detail},
    );
    await refresh();
    return receipt;
  }

  Future<void> removeSaved(String entryId) async {
    await application.removeSaved(entryId);
    await refresh();
  }

  Future<ContentSubscriptionRecord> toggleSubscription(
      ContentHandle handle) async {
    final existing = subscriptionForHandle(handle);
    ContentSubscriptionRecord record;
    if (existing == null) {
      final detail = await application.getDetail(handle);
      record = await application.subscribe(detail.entity);
    } else {
      final nextState = existing.state == ContentSubscriptionState.active
          ? ContentSubscriptionState.paused
          : ContentSubscriptionState.active;
      record = await application.updateSubscriptionState(
        subscriptionId: existing.subscriptionId,
        state: nextState,
      );
    }
    await refresh();
    return record;
  }

  Future<void> unsubscribe(String subscriptionId) async {
    await application.unsubscribe(subscriptionId);
    await refresh();
  }
}
