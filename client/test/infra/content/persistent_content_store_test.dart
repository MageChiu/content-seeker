import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:content_seeker/core/content/content.dart';
import 'package:content_seeker/domain/download/offline_asset.dart';
import 'package:content_seeker/infra/content/persistent_content_store.dart';
import 'package:content_seeker/infra/download/json_offline_asset_repository.dart';
import 'package:content_seeker/platform/storage/app_storage_paths.dart';

void main() {
  group('PersistentContentStore', () {
    test('persists saved detail snapshots and offline assets', () async {
      final root = await Directory.systemTemp.createTemp('content_store_test_');
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });

      final storagePaths = _TestAppStoragePaths(root);
      final assetRepository = JsonOfflineAssetRepository(
        storagePaths: storagePaths,
      );
      final store = PersistentContentStore(
        storagePaths: storagePaths,
        offlineAssetRepository: assetRepository,
      );
      final entity = _entity();
      final detail = ContentDetail(
        entity: entity,
        description: '离线正文',
        sections: const {
          'paragraphs': ['第一段', '第二段'],
        },
      );

      final receipt = await store.save(
        ContentSaveRequest(
          entity: entity,
          mode: ContentSaveMode.bookmark,
          payload: {'detail': detail},
        ),
      );

      expect(receipt.snapshotPath, isNotEmpty);
      expect(File(receipt.snapshotPath).existsSync(), isTrue);
      final page = await store.list(const ContentLibraryQuery(limit: 10));
      expect(page.items, hasLength(1));
      expect(page.items.first.snapshotPath, receipt.snapshotPath);
      expect(page.items.first.offlineAssetId, receipt.offlineAssetId);

      final reloadedStore = PersistentContentStore(
        storagePaths: storagePaths,
        offlineAssetRepository: assetRepository,
      );
      final reloadedDetail = await reloadedStore.getDetail(
        ContentDetailRequest(handle: entity.handle),
      );
      final assets = await assetRepository.listAssets();

      expect(reloadedDetail.description, '离线正文');
      expect(
        (reloadedDetail.sections['paragraphs'] as List<dynamic>).cast<String>(),
        ['第一段', '第二段'],
      );
      expect(assets, hasLength(1));
      expect(assets.first.kind, OfflineAssetKind.snapshot);
      expect(assets.first.localPath, receipt.snapshotPath);
    });
  });
}

ContentEntity _entity() {
  return const ContentEntity(
    handle: ContentHandle(
      id: 'article-1',
      canonicalId: 'sample:article-1',
      type: ContentType.webArticle,
      source: ContentSourceRef(
        sourceId: 'sample-source',
        adapterId: 'sample-adapter',
        displayName: 'Sample',
        capabilities: {ContentCapability.detail, ContentCapability.save},
      ),
    ),
    title: '离线文章',
    summary: '用于测试离线保存',
    readerKind: ContentReaderKind.webArticle,
    capabilities: {
      ContentCapability.detail,
      ContentCapability.open,
      ContentCapability.save,
    },
  );
}

class _TestAppStoragePaths extends AppStoragePaths {
  final Directory root;

  const _TestAppStoragePaths(this.root);

  @override
  Future<Directory> appSupportRoot() async {
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    return root;
  }
}
