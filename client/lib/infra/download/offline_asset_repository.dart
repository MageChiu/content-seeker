import '../../domain/download/offline_asset.dart';

abstract class OfflineAssetRepository {
  Future<List<OfflineAsset>> listAssets();

  Future<void> saveAsset(OfflineAsset asset);

  Future<void> removeAsset(String assetId);

  Future<OfflineAsset?> findByMediaId(String mediaId);
}
